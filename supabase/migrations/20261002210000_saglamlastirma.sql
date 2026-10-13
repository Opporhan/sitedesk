-- Sağlamlaştırma (kullanıcı kararları, 02.10.2026)
-- 1) Çift ödeme koruması kullanıcıdan bağımsız: aynı villa + tutar + tarih 30 sn içinde kim girerse girsin ikinci kez yazılmaz.
-- 2) Banka dosyası aktarımı tek işlem: ya bütün hareketler kaydedilir ya hiçbiri.
-- 3) Günlük sağlık kontrolü: veritabanı kendi durumunu raporlar; sonuçlar health_checks tablosunda tutulur.
-- Mevcut kayıtlar değişmez.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

-- ---------------------------------------------------------------
-- 1) Ödeme kaydı: çift kayıt koruması artık "aynı kullanıcı" şartı aramaz
-- ---------------------------------------------------------------
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

-- ---------------------------------------------------------------
-- 2) Banka hareketlerini tek işlemde kaydet
-- p_items: [{ref, date, amount, value, text, key, learn, link}]
--   value: "u:<birim>" aidat ödemesi · "g:<gelir kategorisi>" · "b:<bütçe kalemi>" gider · "" alma (sadece hafıza)
--   link : elle girilmiş ödemenin kimliği (yeni ödeme yazılmaz, o ödeme harekete bağlanır)
-- Daha önce aktarılmış hareket (aynı banka kimliği) atlanır ve sayılır; bu bir hata değildir.
-- Başka HER hata (geçersiz tarih, başka sitenin birimi, bilinmeyen bütçe kalemi…) işlemi tümüyle geri alır.
-- ---------------------------------------------------------------
create function public.save_bank_items(p_site_id uuid, p_items jsonb)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  r jsonb;
  v_kind text;
  v_target text;
  v_amount numeric;
  v_date date;
  v_ref text;
  v_note text;
  v_item_name text;
  v_unit_site uuid;
  v_line integer := 0;
  c_aidat integer := 0; c_linked integer := 0; c_gelir integer := 0; c_gider integer := 0;
  c_skipped integer := 0; c_learned integer := 0;
  v_today date := (now() at time zone 'Europe/Istanbul')::date;
begin
  if not public.has_site_role(p_site_id, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 5000 then
    raise exception 'Hareket listesi hatalı' using errcode = '22023';
  end if;

  for r in select * from jsonb_array_elements(p_items) loop
    v_line := v_line + 1;
    v_kind := left(coalesce(r->>'value', ''), 1);
    v_target := substr(coalesce(r->>'value', ''), 3);
    v_amount := round((r->>'amount')::numeric, 2);
    v_date := (r->>'date')::date;
    v_ref := nullif(trim(r->>'ref'), '');
    v_note := left(case when length(trim(coalesce(r->>'text', ''))) >= 3 then trim(r->>'text') else 'Banka hareketi' end, 200);
    v_item_name := null;

    if v_ref is null or v_amount is null or v_amount = 0 or v_date is null or v_date > v_today then
      raise exception '%. hareket geçersiz (tarih, tutar veya kimlik)', v_line using errcode = '22023';
    end if;

    begin
      if v_kind = 'u' and v_amount > 0 then
        select site_id into v_unit_site from public.units where id = v_target::uuid;
        if v_unit_site is distinct from p_site_id then
          raise exception '%. hareket: birim bu siteye ait değil', v_line using errcode = '22023';
        end if;
        if nullif(r->>'link', '') is not null then
          if not exists (select 1 from public.payments where id = (r->>'link')::uuid and site_id = p_site_id and unit_id = v_target::uuid) then
            raise exception '%. hareket: eşleşen ödeme bu birime ait değil', v_line using errcode = '22023';
          end if;
          perform public.link_payment_bank_ref((r->>'link')::uuid, v_ref, v_date, v_amount);
          c_linked := c_linked + 1;
        else
          perform public.record_payment(v_target::uuid, v_amount, v_date, 'Banka: ' || v_note, v_ref);
          c_aidat := c_aidat + 1;
        end if;
      elsif v_kind = 'g' and v_amount > 0 then
        if v_target not in ('Ortak alan kira geliri (baz istasyonu, reklam vb.)', 'Banka faiz geliri', 'Bağış', 'Diğer') then
          raise exception '%. hareket: gelir kategorisi geçersiz', v_line using errcode = '22023';
        end if;
        insert into public.cash_entries (site_id, kind, category, description, amount, entry_date, bank_ref)
        values (p_site_id, 'gelir', v_target, v_note, v_amount, v_date, v_ref);
        c_gelir := c_gelir + 1;
      elsif v_kind = 'b' and v_amount < 0 then
        select name into v_item_name from public.budget_items where id = v_target::uuid and site_id = p_site_id;
        if v_item_name is null then
          raise exception '%. hareket: bütçe kalemi bulunamadı', v_line using errcode = '22023';
        end if;
        insert into public.cash_entries (site_id, kind, category, budget_item_id, description, amount, entry_date, bank_ref)
        values (p_site_id, 'gider', v_item_name, v_target::uuid, v_note, -v_amount, v_date, v_ref);
        c_gider := c_gider + 1;
      elsif coalesce(r->>'value', '') <> '' then
        raise exception '%. hareket: nereye kaydedileceği anlaşılamadı', v_line using errcode = '22023';
      end if;
    exception when unique_violation then
      -- Bu hareket daha önce aktarılmış: atla (hafızaya da yazma)
      c_skipped := c_skipped + 1;
      continue;
    end;

    -- Hafıza: bir sonraki dosyada aynı gönderen/açıklama kendiliğinden buraya gelsin
    if coalesce((r->>'learn')::boolean, false) and length(coalesce(r->>'key', '')) >= 3 then
      insert into public.bank_rules (site_id, match_key, target, unit_id, category, updated_at)
      values (p_site_id, r->>'key',
              case v_kind when 'u' then 'aidat' when 'g' then 'gelir' when 'b' then 'gider' else 'alma' end,
              case when v_kind = 'u' then v_target::uuid end,
              case v_kind when 'g' then v_target when 'b' then v_item_name end,
              now())
      on conflict (site_id, match_key) do update
        set target = excluded.target, unit_id = excluded.unit_id, category = excluded.category, updated_at = excluded.updated_at;
      c_learned := c_learned + 1;
    end if;
  end loop;

  return jsonb_build_object('aidat', c_aidat, 'linked', c_linked, 'gelir', c_gelir, 'gider', c_gider,
                            'skipped', c_skipped, 'learned', c_learned);
end;
$$;

revoke execute on function public.save_bank_items(uuid, jsonb) from public, anon;
grant execute on function public.save_bank_items(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------
-- 3) Sağlık kontrolü
-- ---------------------------------------------------------------
-- Günlük kontrol sonuçları (sadece sunucu yazar ve okur; hiçbir kullanıcı rolünün erişimi yok)
create table public.health_checks (
  id uuid primary key default gen_random_uuid(),
  checked_at timestamptz not null default now(),
  ok boolean not null,
  problems jsonb not null default '[]'::jsonb
);
create index on public.health_checks (checked_at desc);
alter table public.health_checks enable row level security;
revoke all on public.health_checks from public, anon, authenticated;

-- Veritabanının kendi durumu: bu ayın aidatı eksik birimler, zamanlayıcı hataları, eksik/kapalı zamanlanmış işler
create function public.health_report()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'period', public.current_period(),
    -- Tutarı girilmiş ama bu ayın aidatı (iptal dahil hiçbir kaydı) olmayan birimler
    'missing_dues', coalesce((
      select jsonb_agg(jsonb_build_object('site', x.name, 'count', x.n))
      from (
        select s.name, count(*) as n
        from public.units u join public.sites s on s.id = u.site_id
        where exists (select 1 from public.unit_due_rates r where r.unit_id = u.id and r.valid_from <= public.current_period())
          and not exists (select 1 from public.dues d where d.unit_id = u.id and d.period = public.current_period() and d.kind = 'aidat')
        group by s.name
      ) x), '[]'::jsonb),
    -- Son 26 saatte hata veren zamanlanmış işler
    'cron_failed', coalesce((
      select jsonb_agg(jsonb_build_object('job', j.jobname, 'at', d.start_time, 'message', left(d.return_message, 200)))
      from cron.job_run_details d join cron.job j on j.jobid = d.jobid
      where d.status = 'failed' and d.start_time > now() - interval '26 hours'), '[]'::jsonb),
    -- Olması gereken zamanlanmış işlerden eksik veya kapalı olanlar
    'cron_missing', coalesce((
      select jsonb_agg(n) from unnest(array['aylik-aidat', 'gecikme-tazminati', 'ziyaretci-temizlik']) n
      where not exists (select 1 from cron.job j where j.jobname = n and j.active)), '[]'::jsonb)
  );
$$;

revoke execute on function public.health_report() from public, anon, authenticated;
grant execute on function public.health_report() to service_role;
