-- Adım 7: Ödemeler, en eski borçtan düşme, iptal
-- Ödeme–borç eşleştirmesi saklanmaz, her seferinde hesaplanır (due_balances görünümü):
-- evin bütün aktif ödemeleri toplanır ve borçlara en eskiden başlayarak dağıtılır.
-- Böylece iptal ve fazla ödeme (avans) her zaman doğru sonuç verir.

create type public.payment_method as enum ('havale', 'nakit');
create type public.payment_status as enum ('aktif', 'iptal');

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null,
  site_id uuid not null,
  amount numeric(12, 2) not null check (amount > 0),
  paid_on date not null,
  method public.payment_method not null default 'havale',
  note text,
  status public.payment_status not null default 'aktif',
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users (id),
  cancel_reason text,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id),
  foreign key (unit_id, site_id) references public.units (id, site_id) on delete restrict
);

create index on public.payments (unit_id) where status = 'aktif';
create index on public.payments (site_id, paid_on);
create index on public.dues (unit_id, period) where status = 'aktif';

-- Ödeme sadece fonksiyonla yazılır / iptal edilir; tabloya doğrudan yazılamaz
revoke all on public.payments from anon, authenticated;
grant select on public.payments to authenticated;
alter table public.payments enable row level security;

create policy "ödeme görme" on public.payments
  for select to authenticated
  using (
    (select public.is_platform_admin())
    or public.has_site_role(site_id, '{yonetici}')
    or public.is_unit_resident(unit_id)
  );

-- ---------------------------------------------------------------
-- Hesaplanan bakiyeler (görünümler, okuyan kişinin yetkisiyle çalışır)
-- ---------------------------------------------------------------

-- Her aktif borç için: ne kadarı ödendi, ne kadarı kaldı (ödeme en eski borçtan düşülür)
create view public.due_balances with (security_invoker = true) as
with d as (
  select id, unit_id, site_id, period, amount, due_date,
         sum(amount) over (partition by unit_id order by period, id) as cumulative
  from public.dues
  where status = 'aktif'
),
p as (
  select unit_id, sum(amount) as paid
  from public.payments
  where status = 'aktif'
  group by unit_id
),
x as (
  select d.*, least(d.amount, greatest(0, coalesce(p.paid, 0) - (d.cumulative - d.amount))) as paid_amount
  from d left join p using (unit_id)
)
select id as due_id, unit_id, site_id, period, amount, due_date, paid_amount,
       amount - paid_amount as remaining,
       case
         when paid_amount >= amount then 'odendi'
         when paid_amount > 0 then 'kismi'
         else 'odenmedi'
       end as payment_state,
       (amount - paid_amount > 0 and due_date < (now() at time zone 'Europe/Istanbul')::date) as overdue
from x;

-- Her ev için toplam: borç (+) veya avans (−)
create view public.unit_balances with (security_invoker = true) as
select u.id as unit_id, u.site_id,
       coalesce(d.total, 0) as total_due,
       coalesce(p.total, 0) as total_paid,
       coalesce(d.total, 0) - coalesce(p.total, 0) as balance
from public.units u
left join (select unit_id, sum(amount) as total from public.dues where status = 'aktif' group by unit_id) d
  on d.unit_id = u.id
left join (select unit_id, sum(amount) as total from public.payments where status = 'aktif' group by unit_id) p
  on p.unit_id = u.id;

grant select on public.due_balances, public.unit_balances to authenticated;
revoke all on public.due_balances, public.unit_balances from anon;

-- ---------------------------------------------------------------
-- İşlemler (sadece site yöneticisi)
-- ---------------------------------------------------------------

create function public.record_payment(
  p_unit_id uuid, p_amount numeric, p_paid_on date, p_method public.payment_method, p_note text default null
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
  v_id uuid;
begin
  select site_id into v_site from public.units where id = p_unit_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Tutar sıfırdan büyük olmalı' using errcode = '22023';
  end if;
  if p_paid_on is null or p_paid_on > (now() at time zone 'Europe/Istanbul')::date then
    raise exception 'Ödeme tarihi ileri bir tarih olamaz' using errcode = '22023';
  end if;

  insert into public.payments (unit_id, site_id, amount, paid_on, method, note)
  values (p_unit_id, v_site, round(p_amount, 2), p_paid_on, p_method, nullif(trim(p_note), ''))
  returning id into v_id;
  return v_id;
end;
$$;

create function public.cancel_payment(p_payment_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
begin
  select site_id into v_site from public.payments where id = p_payment_id;
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
end;
$$;

create function public.cancel_due(p_due_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
begin
  select site_id into v_site from public.dues where id = p_due_id;
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
end;
$$;

revoke execute on function public.record_payment(uuid, numeric, date, public.payment_method, text) from public, anon;
revoke execute on function public.cancel_payment(uuid, text) from public, anon;
revoke execute on function public.cancel_due(uuid, text) from public, anon;
grant execute on function public.record_payment(uuid, numeric, date, public.payment_method, text) to authenticated;
grant execute on function public.cancel_payment(uuid, text) to authenticated;
grant execute on function public.cancel_due(uuid, text) to authenticated;

-- ---------------------------------------------------------------
-- İptal edilen ay tekrar yazılmasın: o ay için herhangi bir kayıt varsa atla
-- ---------------------------------------------------------------
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
    and not exists (select 1 from public.dues d where d.unit_id = u.id and d.period = v_period)
  on conflict (unit_id, period) where status <> 'iptal' do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.generate_monthly_dues(date, uuid) from public, anon, authenticated;
