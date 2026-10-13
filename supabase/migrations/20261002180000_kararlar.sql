-- Kullanıcı kararları (02.10.2026, para denetimi sonrası)
-- 1) Elle girilmiş ödeme, banka hareketine bağlanabilir (yeni ödeme yazmadan).
-- 2) Makbuzun "ödemenin karşılığı" ödeme kaydedilirken saklanır ve bir daha değişmez.
-- 3) Ödeme dağıtımı: tazminat da kendi tarihiyle sıraya girer ("tazminat en son" kuralı kalktı).
-- 4) Gecikme tazminatı ödemenin gerçek tarihine göre gün gün hesaplanır; geç girilen ödeme, iptal vb.
--    sonrasında etkilenen ayların tazminatı kendiliğinden yeniden hesaplanır.
-- 5) Asıl borç iptal edilince ona bağlı tazminat da aynı nedenle iptal olur.

set local lock_timeout = '15s';
set local statement_timeout = '120s';

-- ---------------------------------------------------------------
-- 1) Elle girilmiş ödemeyi banka hareketine bağlama
-- ---------------------------------------------------------------
drop trigger bank_ref_once on public.payments;
create trigger bank_ref_once before insert or update of bank_ref on public.payments
  for each row execute function public.bank_ref_once();

-- Aynı tutar, tarihi en fazla 5 gün farklı, elle girilmiş (banka kimliği olmayan) geçerli ödeme
create function public.link_payment_bank_ref(p_payment_id uuid, p_bank_ref text, p_date date, p_amount numeric)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
  v_ref text := nullif(trim(p_bank_ref), '');
begin
  select site_id into v_site from public.payments where id = p_payment_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if v_ref is null or p_date is null or p_amount is null then
    raise exception 'Banka hareketi eksik' using errcode = '22023';
  end if;

  update public.payments
  set bank_ref = v_ref
  where id = p_payment_id and status = 'aktif' and bank_ref is null
    and amount = round(p_amount, 2) and abs(paid_on - p_date) <= 5;
  if not found then
    raise exception 'Ödeme bu banka hareketiyle eşleşmiyor' using errcode = '22023';
  end if;
end;
$$;

revoke execute on function public.link_payment_bank_ref(uuid, text, date, numeric) from public, anon;
grant execute on function public.link_payment_bank_ref(uuid, text, date, numeric) to authenticated;

-- ---------------------------------------------------------------
-- 3) Ödeme dağıtımı: en eski borç önce, tazminat dahil (aynı ay ve son ödeme gününde asıl borç önce)
-- ---------------------------------------------------------------
create or replace view public.due_balances with (security_invoker = true) as
  with d as (
    select dues.id, dues.unit_id, dues.site_id, dues.period, dues.amount, dues.due_date, dues.kind, dues.description,
           sum(dues.amount) over (partition by dues.unit_id
                                  order by dues.period, dues.due_date, (dues.kind = 'tazminat'), dues.id) as cumulative
    from public.dues
    where dues.status = 'aktif'
  ), p as (
    select payments.unit_id, sum(payments.amount) as paid
    from public.payments
    where payments.status = 'aktif'
    group by payments.unit_id
  ), x as (
    select d.*, least(d.amount, greatest(0::numeric, coalesce(p.paid, 0) - (d.cumulative - d.amount))) as paid_amount
    from d left join p using (unit_id)
  )
  select id as due_id, unit_id, site_id, period, amount, due_date, paid_amount,
         amount - paid_amount as remaining,
         case when paid_amount >= amount then 'odendi' when paid_amount > 0 then 'kismi' else 'odenmedi' end as payment_state,
         (amount - paid_amount > 0 and due_date < (now() at time zone 'Europe/Istanbul')::date) as overdue,
         kind, description
  from x;

-- ---------------------------------------------------------------
-- 2) Makbuz: ödemenin karşılığı kayıt anında saklanır, sonradan değişmez
-- ---------------------------------------------------------------
alter table public.payments add column covered jsonb;

-- Mevcut ödemeler: bugün makbuzda görünen karşılık aynen saklanır (ödemeler tarih sırasıyla, borçlar en eskiden)
alter table public.payments disable trigger audit;
with pay as (
  select id, unit_id, amount,
         sum(amount) over (partition by unit_id order by paid_on, created_at, id) as upto
  from public.payments where status = 'aktif'
), due as (
  select id, unit_id, kind, period, description, amount,
         sum(amount) over (partition by unit_id order by period, due_date, (kind = 'tazminat'), id) as upto
  from public.dues where status = 'aktif'
), part as (
  select pay.id as payment_id, due.id as due_id, due.kind, due.period, due.description, due.upto,
         least(due.upto, pay.upto) - greatest(due.upto - due.amount, pay.upto - pay.amount) as amount
  from pay join due using (unit_id)
)
update public.payments p
set covered = coalesce((
  select jsonb_agg(jsonb_build_object('due_id', part.due_id, 'kind', part.kind, 'period', part.period,
                                      'description', part.description, 'amount', part.amount) order by part.upto)
  from part where part.payment_id = p.id and part.amount > 0), '[]'::jsonb)
where p.status = 'aktif';
alter table public.payments enable trigger audit;

-- Yeni ödeme: o an kalan borçlara en eskiden başlayarak sayılır; artan kısım avanstır
create function public.payment_snapshot()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_left numeric := new.amount;
  v_part numeric;
  v_covered jsonb := '[]'::jsonb;
  r record;
begin
  if tg_op = 'UPDATE' then
    if new.covered is distinct from old.covered or new.amount <> old.amount or new.unit_id <> old.unit_id then
      raise exception 'Ödemenin tutarı ve karşılığı değiştirilemez' using errcode = '42501';
    end if;
    return new;
  end if;

  -- Aynı villaya aynı anda iki ödeme girilirse sırayla hesaplansın
  perform pg_advisory_xact_lock(hashtext('odeme-' || new.unit_id::text));
  for r in
    select b.due_id, b.kind, b.period, b.description, b.remaining
    from public.due_balances b
    where b.unit_id = new.unit_id and b.remaining > 0
    order by b.period, b.due_date, (b.kind = 'tazminat'), b.due_id
  loop
    exit when v_left <= 0;
    v_part := least(r.remaining, v_left);
    v_left := v_left - v_part;
    v_covered := v_covered || jsonb_build_object('due_id', r.due_id, 'kind', r.kind, 'period', r.period,
                                                 'description', r.description, 'amount', v_part);
  end loop;
  new.covered := v_covered;
  return new;
end;
$$;

revoke execute on function public.payment_snapshot() from public, anon, authenticated;

create trigger payment_snapshot before insert or update on public.payments
  for each row execute function public.payment_snapshot();

-- ---------------------------------------------------------------
-- 4) Gecikme tazminatı: ödemenin gerçek tarihine göre
-- ---------------------------------------------------------------
alter table public.dues
  add column fee_rate numeric(4, 2),                   -- tazminat satırının yazıldığı oran (yeniden hesapta aynı oran kullanılır)
  add column recalculated boolean not null default false; -- sistem yeniden hesaplarken iptal etti (elle iptal değil)

-- Elle iptal edilen tazminat yeniden yazılmaz (fonksiyon kontrol eder); yeniden hesaplanan yazılabilir
drop index public.dues_one_fee_per_month;
create unique index dues_one_fee_per_month on public.dues (source_due_id, period) where kind = 'tazminat' and status = 'aktif';
create index dues_fee_source on public.dues (source_due_id, period) where kind = 'tazminat';

-- Bir birimin p_period ayının 1'inde yazılması gereken tazminatlar (bir önceki ayın gecikme günleri için).
-- Her gün için o güne kadar YAPILMIŞ (paid_on) ödemelerle kalan borç bulunur:
--   tazminat = o ayın gecikilen günlerindeki kalan borçların toplamı × aylık oran ÷ 30
-- Ödemenin yapıldığı gün gecikme günü sayılır (10'unda son ödeme, 31'inde ödeme → 21 gün).
create function public.late_fee_expected(p_unit_id uuid, p_period date)
returns table (source_due_id uuid, days integer, amount numeric, rate numeric)
language sql stable security definer set search_path = ''
as $$
  with s as (
    select st.late_fee_rate as rate, st.late_fee_since as since
    from public.units u join public.sites st on st.id = u.site_id
    where u.id = p_unit_id and st.late_fee_enabled and st.late_fee_since is not null and st.late_fee_rate > 0
  ), d as (
    select dd.id, dd.kind, dd.amount, dd.due_date,
           sum(dd.amount) over (order by dd.period, dd.due_date, (dd.kind = 'tazminat'), dd.id) - dd.amount as before
    from public.dues dd
    where dd.unit_id = p_unit_id and dd.status = 'aktif'
  ), day as materialized ( -- her gün için bir kez hesaplansın
    select g::date as day,
           coalesce((select sum(p.amount) from public.payments p
                     where p.unit_id = p_unit_id and p.status = 'aktif' and p.paid_on < g::date), 0) as paid
    from generate_series((p_period - interval '1 month')::date, p_period - 1, interval '1 day') g
  ), x as (
    select d.id, d.amount - least(d.amount, greatest(0::numeric, day.paid - d.before)) as remaining
    from d cross join day cross join s
    where d.kind in ('aidat', 'ek') and day.day > d.due_date and day.day >= s.since
  ), t as (
    select x.id, (count(*) filter (where x.remaining > 0))::integer as days, sum(x.remaining) as total
    from x group by x.id
  )
  select t.id, t.days, round(t.total * r.rate / 100 / 30, 2), r.rate
  from t cross join s
  cross join lateral (
    select coalesce((select f.fee_rate from public.dues f
                     where f.source_due_id = t.id and f.period = p_period and f.kind = 'tazminat' and f.fee_rate is not null
                     order by f.created_at limit 1), s.rate) as rate
  ) r
  where t.days > 0 and round(t.total * r.rate / 100 / 30, 2) > 0;
$$;

revoke execute on function public.late_fee_expected(uuid, date) from public, anon, authenticated;

-- Bir birimin bir ayındaki tazminat satırlarını olması gerekenle eşitler; yeni yazılan satır sayısını döner.
-- Tutarı tutmayan satır "yeniden hesaplandı" diye iptal edilir ve doğrusu yazılır. Elle iptal edilen yeniden yazılmaz.
create function public.apply_late_fees(p_unit_id uuid, p_period date)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_count integer;
  v_expected jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(e)), '[]'::jsonb) into v_expected from public.late_fee_expected(p_unit_id, p_period) e;

  update public.dues f
  set status = 'iptal', cancelled_at = now(), cancelled_by = auth.uid(),
      cancel_reason = 'Ödeme tarihine göre yeniden hesaplandı', recalculated = true
  where f.unit_id = p_unit_id and f.kind = 'tazminat' and f.period = p_period and f.status = 'aktif'
    and f.amount is distinct from (
      select e.amount from jsonb_to_recordset(v_expected) as e(source_due_id uuid, amount numeric)
      where e.source_due_id = f.source_due_id);

  insert into public.dues (unit_id, site_id, period, amount, due_date, kind, description, source_due_id, fee_rate)
  select src.unit_id, src.site_id, p_period, e.amount,
         make_date(extract(year from p_period)::int, extract(month from p_period)::int, st.due_day),
         'tazminat',
         left(format('Gecikme tazminatı – %s (%s gün)',
                     case when src.kind = 'ek' then src.description
                          else (array['Ocak','Şubat','Mart','Nisan','Mayıs','Haziran','Temmuz','Ağustos','Eylül','Ekim','Kasım','Aralık'])[extract(month from src.period)::int]
                               || ' ' || extract(year from src.period)::int || ' aidatı' end,
                     e.days), 200),
         src.id, e.rate
  from jsonb_to_recordset(v_expected) as e(source_due_id uuid, days integer, amount numeric, rate numeric)
  join public.dues src on src.id = e.source_due_id
  join public.sites st on st.id = src.site_id
  where not exists (
    select 1 from public.dues f
    where f.source_due_id = e.source_due_id and f.period = p_period and f.kind = 'tazminat'
      and (f.status = 'aktif' or not f.recalculated));

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.apply_late_fees(uuid, date) from public, anon, authenticated;

-- Geçmişe dönük bir değişiklikten (geç girilen ödeme, iptal, geçmiş tarihli ek ücret) sonra:
-- p_from gününü izleyen aydan bu aya kadar birimin tazminatları sırayla yeniden hesaplanır.
create function public.recalc_late_fees(p_unit_id uuid, p_from date)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_since date;
  v_period date;
begin
  select st.late_fee_since into v_since
  from public.units u join public.sites st on st.id = u.site_id
  where u.id = p_unit_id and st.late_fee_enabled and st.late_fee_since is not null and st.late_fee_rate > 0;
  if v_since is null or p_from is null then
    return;
  end if;
  v_period := (date_trunc('month', greatest(p_from, v_since)) + interval '1 month')::date;
  while v_period <= public.current_period() loop
    perform public.apply_late_fees(p_unit_id, v_period);
    v_period := (v_period + interval '1 month')::date;
  end loop;
end;
$$;

revoke execute on function public.recalc_late_fees(uuid, date) from public, anon, authenticated;

-- Aylık yazım (zamanlayıcı): tazminatı açık sitelerin bütün birimleri için p_period ayı
create or replace function public.generate_late_fees(p_period date default null)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_period date := coalesce(p_period, public.current_period());
  v_count integer := 0;
  r record;
begin
  if extract(day from v_period) <> 1 then
    raise exception 'Dönem ayın 1''i olmalı';
  end if;
  for r in
    select u.id from public.units u join public.sites st on st.id = u.site_id
    where st.late_fee_enabled and st.late_fee_since is not null and st.late_fee_rate > 0
      and v_period > date_trunc('month', st.late_fee_since)::date
  loop
    v_count := v_count + public.apply_late_fees(r.id, v_period);
  end loop;
  return v_count;
end;
$$;

revoke execute on function public.generate_late_fees(date) from public, anon, authenticated;

-- Ödeme kaydı: geçmiş tarihli ödeme, etkilediği ayların tazminatını yeniden hesaplatır
create or replace function public.record_payment(
  p_unit_id uuid, p_amount numeric, p_paid_on date, p_note text default null, p_bank_ref text default null
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
  v_id uuid;
  v_ref text := nullif(trim(p_bank_ref), '');
begin
  select site_id into v_site from public.units where id = p_unit_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if p_amount is null or round(p_amount, 2) <= 0 then
    raise exception 'Tutar sıfırdan büyük olmalı' using errcode = '22023';
  end if;
  if p_paid_on is null or p_paid_on > (now() at time zone 'Europe/Istanbul')::date then
    raise exception 'Ödeme tarihi ileri bir tarih olamaz' using errcode = '22023';
  end if;

  if v_ref is null then
    -- Aynı villaya aynı anda gelen iki istek sıraya girer; ikincisi birincinin kaydını görür
    perform pg_advisory_xact_lock(hashtext('odeme-' || p_unit_id::text));
    if exists (
      select 1 from public.payments
      where unit_id = p_unit_id and status = 'aktif' and bank_ref is null
        and amount = round(p_amount, 2) and paid_on = p_paid_on
        and created_by is not distinct from auth.uid()
        and created_at > now() - interval '30 seconds'
    ) then
      raise exception 'Bu ödeme az önce kaydedildi' using errcode = 'SD001';
    end if;
  end if;

  insert into public.payments (unit_id, site_id, amount, paid_on, method, note, bank_ref)
  values (p_unit_id, v_site, round(p_amount, 2), p_paid_on, 'havale', nullif(trim(p_note), ''), v_ref)
  returning id into v_id;
  perform public.recalc_late_fees(p_unit_id, p_paid_on);
  return v_id;
end;
$$;

create or replace function public.cancel_payment(p_payment_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
  v_unit uuid;
  v_paid_on date;
begin
  select site_id, unit_id, paid_on into v_site, v_unit, v_paid_on from public.payments where id = p_payment_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'İptal nedeni yazılmalı' using errcode = '22023';
  end if;

  update public.payments
  set status = 'iptal', cancelled_at = now(), cancelled_by = auth.uid(), cancel_reason = trim(p_reason)
  where id = p_payment_id and status = 'aktif';
  if not found then
    raise exception 'Ödeme zaten iptal edilmiş' using errcode = '22023';
  end if;
  perform public.recalc_late_fees(v_unit, v_paid_on);
end;
$$;

-- 5) Borç iptali: asıl borca bağlı tazminatlar da aynı nedenle iptal olur (işlem geçmişine tek tek yazılır)
create or replace function public.cancel_due(p_due_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
  v_unit uuid;
  v_due_date date;
begin
  select site_id, unit_id, due_date into v_site, v_unit, v_due_date from public.dues where id = p_due_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'İptal nedeni yazılmalı' using errcode = '22023';
  end if;

  update public.dues
  set status = 'iptal', cancelled_at = now(), cancelled_by = auth.uid(), cancel_reason = trim(p_reason)
  where id = p_due_id and status = 'aktif';
  if not found then
    raise exception 'Borç zaten iptal edilmiş' using errcode = '22023';
  end if;

  update public.dues
  set status = 'iptal', cancelled_at = now(), cancelled_by = auth.uid(), cancel_reason = trim(p_reason)
  where source_due_id = p_due_id and status = 'aktif';

  perform public.recalc_late_fees(v_unit, v_due_date);
end;
$$;

-- Ek ücret: son ödeme tarihi geçmişteyse tazminatlar yeniden hesaplanır
create or replace function public.add_extra_charge(p_site_id uuid, p_unit_ids uuid[], p_amount numeric, p_description text, p_due_date date)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_count integer;
begin
  if not public.is_platform_admin() then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if p_amount is null or p_amount <= 0 or p_amount >= 100000000 then
    raise exception 'Tutar hatalı' using errcode = '22023';
  end if;
  if coalesce(length(trim(p_description)), 0) not between 3 and 200 then
    raise exception 'Açıklama 3-200 karakter olmalı' using errcode = '22023';
  end if;
  if p_due_date is null then
    raise exception 'Son ödeme tarihi gerekli' using errcode = '22023';
  end if;

  insert into public.dues (unit_id, site_id, period, amount, due_date, kind, description)
  select u.id, u.site_id, date_trunc('month', p_due_date)::date, round(p_amount, 2), p_due_date, 'ek', trim(p_description)
  from public.units u
  where u.site_id = p_site_id and (p_unit_ids is null or u.id = any (p_unit_ids));

  get diagnostics v_count = row_count;
  if v_count = 0 then
    raise exception 'Seçili birim yok' using errcode = '22023';
  end if;

  perform public.recalc_late_fees(u.id, p_due_date)
  from public.units u
  where u.site_id = p_site_id and (p_unit_ids is null or u.id = any (p_unit_ids));
  return v_count;
end;
$$;
