-- Adım 2: Veritabanı temeli ve güvenlik
-- Site → Blok → Ev, roller ve "kim neyi görebilir" kuralları (RLS).

-- ---------------------------------------------------------------
-- Türler
-- ---------------------------------------------------------------
create type public.site_type as enum ('villa', 'apartman');
create type public.unit_type as enum ('villa', 'daire');
create type public.site_role as enum ('yonetici', 'danisma', 'sakin');
create type public.resident_relation as enum ('malik', 'kiraci');

-- ---------------------------------------------------------------
-- Tablolar
-- ---------------------------------------------------------------

-- Sistem yöneticileri (uygulamanın sahibi). Siteye bağlı değildir.
-- Bu tabloya uygulamadan yazılamaz, sadece SQL ile eklenir.
create table public.platform_admins (
  user_id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '',
  phone text,
  created_at timestamptz not null default now()
);

create table public.sites (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  type public.site_type not null,
  address text,
  iban text check (iban ~ '^TR[0-9]{24}$'), -- boşluksuz saklanır
  iban_holder text,
  due_day smallint not null default 10 check (due_day between 1 and 28),
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id)
);

create table public.blocks (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  name text not null check (length(trim(name)) > 0),
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id),
  unique (site_id, name),
  unique (id, site_id) -- alt tabloların site_id'si tutarlı olsun diye
);

create table public.units (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  block_id uuid not null,
  no text not null check (length(trim(no)) > 0),
  type public.unit_type not null,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id),
  -- Ev, başka bir sitenin bloğuna bağlanamaz
  foreign key (block_id, site_id) references public.blocks (id, site_id) on delete restrict,
  unique (block_id, no),
  unique (id, site_id)
);

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  site_id uuid not null references public.sites (id) on delete restrict,
  role public.site_role not null,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id),
  -- Aynı kişi aynı sitede hem yönetici hem sakin olabilir
  unique (user_id, site_id, role)
);

create table public.unit_residents (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null,
  site_id uuid not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  relation public.resident_relation not null,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id),
  -- Sakin, başka bir sitenin evine bağlanamaz
  foreign key (unit_id, site_id) references public.units (id, site_id) on delete restrict,
  unique (unit_id, user_id)
);

-- İndeksler (güvenlik kuralları ve listeler hızlı çalışsın)
create index on public.blocks (site_id);
create index on public.units (site_id);
create index on public.units (block_id, site_id);
create index on public.memberships (site_id);
create index on public.unit_residents (user_id);
create index on public.unit_residents (site_id);
create index on public.unit_residents (unit_id, site_id);

-- ---------------------------------------------------------------
-- Yardımcı fonksiyonlar
-- security definer: kendi içinde RLS'e takılmadan kontrol yapar.
-- search_path boş: başka şemadan sahte tablo/fonksiyon enjekte edilemez.
-- ---------------------------------------------------------------
create function public.is_platform_admin()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.platform_admins where user_id = (select auth.uid())
  );
$$;

create function public.has_site_role(p_site_id uuid, p_roles public.site_role[])
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.memberships
    where user_id = (select auth.uid()) and site_id = p_site_id and role = any (p_roles)
  );
$$;

create function public.is_site_member(p_site_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.memberships
    where user_id = (select auth.uid()) and site_id = p_site_id
  );
$$;

create function public.is_unit_resident(p_unit_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.unit_residents
    where user_id = (select auth.uid()) and unit_id = p_unit_id
  );
$$;

-- Aynı sitede, isteyen kişinin görebileceği biri mi? (profil görme için)
create function public.shares_site_as_staff(p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships target
    join public.memberships me
      on me.site_id = target.site_id
     and me.user_id = (select auth.uid())
     and me.role in ('yonetici', 'danisma')
    where target.user_id = p_user_id
  );
$$;

revoke execute on function public.is_platform_admin() from public, anon;
revoke execute on function public.has_site_role(uuid, public.site_role[]) from public, anon;
revoke execute on function public.is_site_member(uuid) from public, anon;
revoke execute on function public.is_unit_resident(uuid) from public, anon;
revoke execute on function public.shares_site_as_staff(uuid) from public, anon;
grant execute on function public.is_platform_admin() to authenticated;
grant execute on function public.has_site_role(uuid, public.site_role[]) to authenticated;
grant execute on function public.is_site_member(uuid) to authenticated;
grant execute on function public.is_unit_resident(uuid) to authenticated;
grant execute on function public.shares_site_as_staff(uuid) to authenticated;

-- Yeni kullanıcı (davet) oluşunca profilini aç
create function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (user_id, full_name, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.raw_user_meta_data ->> 'phone'
  );
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Daha önce açılmış kullanıcılar için de profil oluştur
insert into public.profiles (user_id, full_name)
select id, coalesce(raw_user_meta_data ->> 'full_name', '') from auth.users
on conflict do nothing;

-- ---------------------------------------------------------------
-- Yetkiler: giriş yapmamış (anon) hiçbir tabloya erişemez.
-- Giriş yapmış kullanıcı sadece RLS kurallarının izin verdiği satırları görür.
-- ---------------------------------------------------------------
revoke all on public.platform_admins, public.profiles, public.sites, public.blocks,
  public.units, public.memberships, public.unit_residents from anon, authenticated;

grant select on public.platform_admins to authenticated;
grant select, update (full_name, phone) on public.profiles to authenticated;
grant select, insert, update on public.sites to authenticated;
grant select, insert, update, delete on public.blocks, public.units,
  public.memberships, public.unit_residents to authenticated;

alter table public.platform_admins enable row level security;
alter table public.profiles enable row level security;
alter table public.sites enable row level security;
alter table public.blocks enable row level security;
alter table public.units enable row level security;
alter table public.memberships enable row level security;
alter table public.unit_residents enable row level security;

-- platform_admins: kişi sadece kendisinin sistem yöneticisi olup olmadığını görür
create policy "kendi kaydını görür" on public.platform_admins
  for select to authenticated
  using (user_id = (select auth.uid()));

-- profiles
create policy "profil görme" on public.profiles
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select public.is_platform_admin())
    or public.shares_site_as_staff(user_id)
  );

create policy "kendi profilini düzenler" on public.profiles
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- sites: üyeler kendi sitelerini görür; sadece sistem yöneticisi ekler/düzenler
create policy "site görme" on public.sites
  for select to authenticated
  using ((select public.is_platform_admin()) or public.is_site_member(id));

create policy "site ekleme" on public.sites
  for insert to authenticated
  with check ((select public.is_platform_admin()));

create policy "site düzenleme" on public.sites
  for update to authenticated
  using ((select public.is_platform_admin()))
  with check ((select public.is_platform_admin()));

-- blocks: yönetici/danışma sitenin bütün bloklarını, sakin sadece kendi evinin bloğunu görür
create policy "blok görme" on public.blocks
  for select to authenticated
  using (
    (select public.is_platform_admin())
    or public.has_site_role(site_id, '{yonetici,danisma}')
    or exists (
      select 1 from public.units u
      where u.block_id = blocks.id and public.is_unit_resident(u.id)
    )
  );

create policy "blok yönetimi" on public.blocks
  for all to authenticated
  using (public.has_site_role(site_id, '{yonetici}'))
  with check (public.has_site_role(site_id, '{yonetici}'));

-- units: yönetici/danışma bütün evleri, sakin sadece kendi evlerini görür
create policy "ev görme" on public.units
  for select to authenticated
  using (
    (select public.is_platform_admin())
    or public.has_site_role(site_id, '{yonetici,danisma}')
    or public.is_unit_resident(id)
  );

create policy "ev yönetimi" on public.units
  for all to authenticated
  using (public.has_site_role(site_id, '{yonetici}'))
  with check (public.has_site_role(site_id, '{yonetici}'));

-- memberships
create policy "üyelik görme" on public.memberships
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select public.is_platform_admin())
    or public.has_site_role(site_id, '{yonetici}')
  );

-- Sistem yöneticisi her rolü atar (site yöneticisi dahil)
create policy "sistem yöneticisi üyelik yönetimi" on public.memberships
  for all to authenticated
  using ((select public.is_platform_admin()))
  with check ((select public.is_platform_admin()));

-- Site yöneticisi kendi sitesinde sadece danışma ve sakin ekler/çıkarır
create policy "site yöneticisi üyelik yönetimi" on public.memberships
  for all to authenticated
  using (public.has_site_role(site_id, '{yonetici}') and role in ('danisma', 'sakin'))
  with check (public.has_site_role(site_id, '{yonetici}') and role in ('danisma', 'sakin'));

-- unit_residents
create policy "sakin bağlantısı görme" on public.unit_residents
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select public.is_platform_admin())
    or public.has_site_role(site_id, '{yonetici,danisma}')
  );

create policy "sakin bağlantısı yönetimi" on public.unit_residents
  for all to authenticated
  using (public.has_site_role(site_id, '{yonetici}'))
  with check (public.has_site_role(site_id, '{yonetici}'));
