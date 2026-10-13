-- Ek ücret: genel kurul kararıyla toplanan tek seferlik tutar (ör. çatı tamiri), bütün veya seçilen birimlere.
-- Aynı borç tablosunda kind = 'ek' olarak tutulur; böylece ödeme dağıtımı (en eski borçtan), borçlular,
-- hatırlatma ve raporlar ek ücreti de kendiliğinden görür. Mevcut kayıtlar 'aidat' sayılır.
-- "Ayda bir borç" kuralı ve aylık otomatik yazım sadece aidata uygulanır.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

alter table public.dues
  add column kind text not null default 'aidat' check (kind in ('aidat', 'ek')),
  add column description text check (description is null or length(trim(description)) between 3 and 200),
  add constraint dues_extra_needs_description check (kind = 'aidat' or description is not null);

drop index public.dues_one_per_month;
create unique index dues_one_per_month on public.dues (unit_id, period) where status <> 'iptal' and kind = 'aidat';

-- Aylık yazım: sadece aidat (ek ücret olan ay da aidat yazılır)
create or replace function public.generate_monthly_dues(p_period date default null, p_site_id uuid default null)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_period date := coalesce(p_period, public.current_period());
  v_count integer;
begin
  if extract(day from v_period) <> 1 then
    raise exception 'Dönem ayın 1''i olmalı';
  end if;

  insert into public.dues (unit_id, site_id, period, amount, due_date, created_by)
  select u.id, u.site_id, v_period, r.amount,
         make_date(extract(year from v_period)::int, extract(month from v_period)::int, s.due_day),
         null
  from public.units u
  join public.sites s on s.id = u.site_id
  join lateral (
    select amount from public.unit_due_rates
    where unit_id = u.id and valid_from <= v_period
    order by valid_from desc
    limit 1
  ) r on true
  where (p_site_id is null or u.site_id = p_site_id)
    and not exists (select 1 from public.dues d where d.unit_id = u.id and d.period = v_period and d.kind = 'aidat')
  on conflict (unit_id, period) where status <> 'iptal' and kind = 'aidat' do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Borç başına ödenen/kalan: tür ve açıklama da görünür; aynı ay içinde son ödeme gününe göre sıralanır
create or replace view public.due_balances with (security_invoker = true) as
  with d as (
    select dues.id, dues.unit_id, dues.site_id, dues.period, dues.amount, dues.due_date, dues.kind, dues.description,
           sum(dues.amount) over (partition by dues.unit_id order by dues.period, dues.due_date, dues.id) as cumulative
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

-- Ek ücret yaz: sitenin bütün birimlerine (p_unit_ids boş) veya seçilenlere. Sadece sistem yöneticisi (aidat tutarı gibi).
create function public.add_extra_charge(p_site_id uuid, p_unit_ids uuid[], p_amount numeric, p_description text, p_due_date date)
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
  return v_count;
end;
$$;

revoke execute on function public.add_extra_charge(uuid, uuid[], numeric, text, date) from public, anon;
grant execute on function public.add_extra_charge(uuid, uuid[], numeric, text, date) to authenticated;
