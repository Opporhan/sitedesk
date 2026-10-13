-- Adım 6: Aidat tutarları ve aylık borç yazımı
-- Tutarı sistem yöneticisi girer; borcu her ayın 1'inde pg_cron yazar.
-- Aynı ay için bir eve iki borç yazılamaz. Borçlar silinmez.

-- ---------------------------------------------------------------
-- Aidat tutarları (her ev için ayrı, tarihçeli)
-- ---------------------------------------------------------------
create table public.unit_due_rates (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null,
  site_id uuid not null,
  amount numeric(12, 2) not null check (amount > 0),
  valid_from date not null check (extract(day from valid_from) = 1), -- ayın 1'i
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id),
  foreign key (unit_id, site_id) references public.units (id, site_id) on delete restrict,
  unique (unit_id, valid_from)
);

create index on public.unit_due_rates (site_id);

-- ---------------------------------------------------------------
-- Borçlar (aidat)
-- ---------------------------------------------------------------
create type public.due_status as enum ('aktif', 'iptal');

create table public.dues (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null,
  site_id uuid not null,
  period date not null check (extract(day from period) = 1), -- hangi ayın aidatı
  amount numeric(12, 2) not null check (amount > 0),
  due_date date not null,
  status public.due_status not null default 'aktif',
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users (id),
  cancel_reason text,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id), -- otomatik yazımda boş
  foreign key (unit_id, site_id) references public.units (id, site_id) on delete restrict
);

-- Aynı ay için bir eve iki kez aidat yazılmaz (iptal edilmişler hariç)
create unique index dues_one_per_month on public.dues (unit_id, period) where status <> 'iptal';
create index on public.dues (site_id, period);

-- ---------------------------------------------------------------
-- Yetkiler
-- ---------------------------------------------------------------
revoke all on public.unit_due_rates, public.dues from anon, authenticated;
grant select, insert on public.unit_due_rates to authenticated;
-- "varsa güncelle, yoksa ekle" (upsert) için; kural gereği sadece sistem yöneticisi yazabilir
grant update (unit_id, site_id, amount, valid_from) on public.unit_due_rates to authenticated;
grant select on public.dues to authenticated; -- borç sadece fonksiyonla yazılır

alter table public.unit_due_rates enable row level security;
alter table public.dues enable row level security;

create policy "tutar görme" on public.unit_due_rates
  for select to authenticated
  using (
    (select public.is_platform_admin())
    or public.has_site_role(site_id, '{yonetici}')
    or public.is_unit_resident(unit_id)
  );

-- Tutarı sadece sistem yöneticisi girer / düzeltir
create policy "tutar girme" on public.unit_due_rates
  for insert to authenticated
  with check ((select public.is_platform_admin()));

create policy "tutar düzeltme" on public.unit_due_rates
  for update to authenticated
  using ((select public.is_platform_admin()))
  with check ((select public.is_platform_admin()));

create policy "borç görme" on public.dues
  for select to authenticated
  using (
    (select public.is_platform_admin())
    or public.has_site_role(site_id, '{yonetici}')
    or public.is_unit_resident(unit_id)
  );

-- ---------------------------------------------------------------
-- Borç yazma
-- ---------------------------------------------------------------

-- Türkiye saatine göre bu ayın 1'i
create function public.current_period()
returns date
language sql stable set search_path = ''
as $$
  select date_trunc('month', (now() at time zone 'Europe/Istanbul'))::date;
$$;

-- Verilen ay için tutarı girilmiş bütün evlere borç yazar; yazılan sayıyı döner.
-- Kaç kez çalışırsa çalışsın aynı ay için ikinci borç yazılmaz.
create function public.generate_monthly_dues(p_period date default null, p_site_id uuid default null)
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
  where p_site_id is null or u.site_id = p_site_id
  on conflict (unit_id, period) where status <> 'iptal' do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Bu fonksiyonu doğrudan sadece zamanlayıcı (veritabanı) çağırabilir
revoke execute on function public.generate_monthly_dues(date, uuid) from public, anon, authenticated;

-- "Şimdi yaz" butonu: site yöneticisi kendi sitesi için bu ayın aidatını yazar
create function public.generate_dues_now(p_site_id uuid)
returns integer
language plpgsql security definer set search_path = ''
as $$
begin
  if not (public.has_site_role(p_site_id, '{yonetici}') or public.is_platform_admin()) then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  return public.generate_monthly_dues(public.current_period(), p_site_id);
end;
$$;

revoke execute on function public.generate_dues_now(uuid) from public, anon;
grant execute on function public.generate_dues_now(uuid) to authenticated;

-- ---------------------------------------------------------------
-- Zamanlayıcı: her ayın 1'inde (Türkiye saatiyle 03:05'ten itibaren saat başı)
-- Birden fazla çalışması zararsızdır; bir çalışma aksarsa sonraki telafi eder.
-- ---------------------------------------------------------------
create extension if not exists pg_cron;

select cron.schedule(
  'aylik-aidat',
  '5 * 1 * *',
  $$select public.generate_monthly_dues()$$
);
