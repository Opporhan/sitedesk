-- Adım 4: Başlangıç / ayrılış tarihleri ve davet desteği
-- Kayıtlar silinmez; ayrılınca ended_on yazılır ve yetki kapanır.

-- ---------------------------------------------------------------
-- Tarih kolonları
-- ---------------------------------------------------------------
alter table public.memberships
  add column started_on date not null default current_date,
  add column ended_on date,
  add constraint memberships_dates_check check (ended_on is null or ended_on >= started_on);

alter table public.unit_residents
  add column started_on date not null default current_date,
  add column ended_on date,
  add constraint unit_residents_dates_check check (ended_on is null or ended_on >= started_on);

-- Aynı kişi ayrılıp geri dönebilsin: benzersizlik sadece aktif kayıtlar için
alter table public.memberships drop constraint memberships_user_id_site_id_role_key;
create unique index memberships_active_unique
  on public.memberships (user_id, site_id, role) where ended_on is null;

alter table public.unit_residents drop constraint unit_residents_unit_id_user_id_key;
create unique index unit_residents_active_unique
  on public.unit_residents (unit_id, user_id) where ended_on is null;

-- ---------------------------------------------------------------
-- Yetki fonksiyonları: sadece aktif kayıtlar sayılır
-- ---------------------------------------------------------------
create or replace function public.has_site_role(p_site_id uuid, p_roles public.site_role[])
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.memberships
    where user_id = (select auth.uid()) and site_id = p_site_id
      and role = any (p_roles) and ended_on is null
  );
$$;

create or replace function public.is_site_member(p_site_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.memberships
    where user_id = (select auth.uid()) and site_id = p_site_id and ended_on is null
  );
$$;

create or replace function public.is_unit_resident(p_unit_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.unit_residents
    where user_id = (select auth.uid()) and unit_id = p_unit_id and ended_on is null
  );
$$;

-- Yönetici/danışma, sitesindeki kişilerin (eski sakinler dahil) profilini görebilir
create or replace function public.shares_site_as_staff(p_user_id uuid)
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
     and me.ended_on is null
    where target.user_id = p_user_id
  );
$$;

-- ---------------------------------------------------------------
-- Silme yok, sadece tarih ve ilişki güncellenir
-- ---------------------------------------------------------------
revoke delete, update on public.memberships, public.unit_residents from authenticated;
grant update (started_on, ended_on) on public.memberships to authenticated;
grant update (started_on, ended_on, relation) on public.unit_residents to authenticated;

-- Ayrılmış kaydı tekrar "aktif" yapmak yerine yeni kayıt açılır
create function public.prevent_reopen()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if old.ended_on is not null and new.ended_on is null then
    raise exception 'Ayrılmış kayıt tekrar açılamaz; yeni kayıt ekleyin.';
  end if;
  return new;
end;
$$;

create trigger memberships_prevent_reopen
  before update on public.memberships
  for each row execute function public.prevent_reopen();

create trigger unit_residents_prevent_reopen
  before update on public.unit_residents
  for each row execute function public.prevent_reopen();

-- ---------------------------------------------------------------
-- Davet için: e-postadan kullanıcı bulma (sadece sunucu anahtarı çağırabilir)
-- ---------------------------------------------------------------
create function public.find_user_id_by_email(p_email text)
returns uuid
language sql stable security definer set search_path = ''
as $$
  select id from auth.users where lower(email) = lower(trim(p_email)) limit 1;
$$;

revoke execute on function public.find_user_id_by_email(text) from public, anon, authenticated;
grant execute on function public.find_user_id_by_email(text) to service_role;

-- ---------------------------------------------------------------
-- Listelerde ad ve e-posta gösterebilmek için
-- ---------------------------------------------------------------
alter table public.profiles add column email text;
update public.profiles p set email = u.email from auth.users u where u.id = p.user_id;

create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (user_id, full_name, phone, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.raw_user_meta_data ->> 'phone',
    new.email
  );
  return new;
end;
$$;

create function public.sync_user_email()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  update public.profiles set email = new.email where user_id = new.id;
  return new;
end;
$$;

revoke execute on function public.sync_user_email() from public, anon, authenticated;

create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row execute function public.sync_user_email();

-- Üyelik ve ev bağlantısından kişinin profiline doğrudan ulaşılabilsin
alter table public.memberships
  add constraint memberships_profile_fkey foreign key (user_id) references public.profiles (user_id);
alter table public.unit_residents
  add constraint unit_residents_profile_fkey foreign key (user_id) references public.profiles (user_id);
