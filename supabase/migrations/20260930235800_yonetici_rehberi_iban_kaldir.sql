-- Adım 8c (devam): Site yöneticisi rehber kaydı olur, IBAN kaldırılır.
-- Uygulamaya sadece sistem yöneticisi ve danışma görevlisi girer.

-- ---------------------------------------------------------------
-- 1) Site yöneticisi rehberi (uygulamaya girmez)
-- ---------------------------------------------------------------
create table public.site_managers (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  full_name text not null check (length(trim(full_name)) >= 3),
  phone text check (phone ~ '^[1-9][0-9]{9,14}$'),
  started_on date not null default current_date,
  ended_on date,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id),
  check (ended_on is null or ended_on >= started_on)
);

create index on public.site_managers (site_id);

revoke all on public.site_managers from anon, authenticated;
grant select, insert on public.site_managers to authenticated;
grant update (full_name, phone, started_on, ended_on) on public.site_managers to authenticated;
alter table public.site_managers enable row level security;

create policy "yönetici rehberi görme" on public.site_managers
  for select to authenticated
  using ((select public.is_platform_admin()));

create policy "yönetici rehberi ekleme" on public.site_managers
  for insert to authenticated
  with check ((select public.is_platform_admin()));

create policy "yönetici rehberi düzenleme" on public.site_managers
  for update to authenticated
  using ((select public.is_platform_admin()))
  with check ((select public.is_platform_admin()));

create trigger site_managers_prevent_reopen
  before update on public.site_managers
  for each row execute function public.prevent_reopen();

-- Mevcut site yöneticisi hesaplarını rehbere taşı ve girişlerini kapat
insert into public.site_managers (site_id, full_name, phone, started_on, ended_on)
select m.site_id,
       case when length(trim(coalesce(p.full_name, ''))) >= 3 then p.full_name else coalesce(p.email, 'İsimsiz') end,
       case when regexp_replace(coalesce(p.phone, ''), '\D', '', 'g') ~ '^0?5[0-9]{9}$'
            then '90' || right(regexp_replace(p.phone, '\D', '', 'g'), 10) end,
       m.started_on,
       m.ended_on
from public.memberships m
left join public.profiles p on p.user_id = m.user_id
where m.role = 'yonetici';

update public.memberships set ended_on = greatest(started_on, current_date)
where role = 'yonetici' and ended_on is null;

-- ---------------------------------------------------------------
-- 2) IBAN ve alıcı adı kaldırılır (ödemeler uygulamadan geçmez)
-- ---------------------------------------------------------------
alter table public.sites drop column iban, drop column iban_holder;
