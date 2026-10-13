-- Adım 8b: Yönetici odaklı düzen
-- Sakinler uygulamaya girmez; site yöneticisinin tuttuğu rehber kaydıdır (ad, telefon).
-- Sakin hesaplarının bütün yetkileri, "Ödeme yaptım" bildirimi ve dekont deposu kaldırılır.
-- (Dekont deposundaki dosyalar ve depo, depo aracıyla önceden silindi.)

-- ---------------------------------------------------------------
-- 1) Sakin rehberi
-- ---------------------------------------------------------------
create table public.residents (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  full_name text not null check (length(trim(full_name)) >= 3),
  phone text check (phone ~ '^[1-9][0-9]{9,14}$'), -- 905321234567 biçiminde
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id),
  unique (id, site_id)
);

-- Aynı sitede aynı telefon bir kişidir
create unique index residents_site_phone_unique on public.residents (site_id, phone) where phone is not null;
create index on public.residents (site_id);

revoke all on public.residents from anon, authenticated;
grant select, insert on public.residents to authenticated;
grant update (full_name, phone) on public.residents to authenticated;
alter table public.residents enable row level security;

create policy "rehber görme" on public.residents
  for select to authenticated
  using ((select public.is_platform_admin()) or public.has_site_role(site_id, '{yonetici,danisma}'));

create policy "rehber ekleme" on public.residents
  for insert to authenticated
  with check (public.has_site_role(site_id, '{yonetici}'));

create policy "rehber düzenleme" on public.residents
  for update to authenticated
  using (public.has_site_role(site_id, '{yonetici}'))
  with check (public.has_site_role(site_id, '{yonetici}'));

-- ---------------------------------------------------------------
-- 2) Ev bağlantısı kullanıcıdan rehber kaydına geçer
-- ---------------------------------------------------------------
alter table public.unit_residents add column resident_id uuid;

-- Mevcut (deneme) sakinleri rehbere taşı
alter table public.residents add column legacy_user_id uuid;
insert into public.residents (site_id, full_name, phone, legacy_user_id)
select distinct on (ur.site_id, ur.user_id)
       ur.site_id,
       case when length(trim(coalesce(p.full_name, ''))) >= 3 then p.full_name else coalesce(p.email, 'İsimsiz') end,
       case when regexp_replace(coalesce(p.phone, ''), '\D', '', 'g') ~ '^0?5[0-9]{9}$'
            then '90' || right(regexp_replace(p.phone, '\D', '', 'g'), 10) end,
       ur.user_id
from public.unit_residents ur
left join public.profiles p on p.user_id = ur.user_id;

update public.unit_residents ur
set resident_id = r.id
from public.residents r
where r.legacy_user_id = ur.user_id and r.site_id = ur.site_id;

alter table public.residents drop column legacy_user_id;

drop policy "sakin bağlantısı görme" on public.unit_residents;
drop policy "sakin bağlantısı yönetimi" on public.unit_residents;
drop index public.unit_residents_active_unique;
alter table public.unit_residents drop constraint unit_residents_profile_fkey;
alter table public.unit_residents drop column user_id;

alter table public.unit_residents alter column resident_id set not null;
alter table public.unit_residents
  add constraint unit_residents_resident_fkey
  foreign key (resident_id, site_id) references public.residents (id, site_id) on delete restrict;
create unique index unit_residents_active_unique
  on public.unit_residents (unit_id, resident_id) where ended_on is null;
create index on public.unit_residents (resident_id);

create policy "ev bağlantısı görme" on public.unit_residents
  for select to authenticated
  using ((select public.is_platform_admin()) or public.has_site_role(site_id, '{yonetici,danisma}'));

create policy "ev bağlantısı yönetimi" on public.unit_residents
  for all to authenticated
  using (public.has_site_role(site_id, '{yonetici}'))
  with check (public.has_site_role(site_id, '{yonetici}'));

-- ---------------------------------------------------------------
-- 3) Sakin hesaplarının yetkileri kaldırılır
-- ---------------------------------------------------------------
drop policy "blok görme" on public.blocks;
create policy "blok görme" on public.blocks
  for select to authenticated
  using ((select public.is_platform_admin()) or public.has_site_role(site_id, '{yonetici,danisma}'));

drop policy "ev görme" on public.units;
create policy "ev görme" on public.units
  for select to authenticated
  using ((select public.is_platform_admin()) or public.has_site_role(site_id, '{yonetici,danisma}'));

drop policy "tutar görme" on public.unit_due_rates;
create policy "tutar görme" on public.unit_due_rates
  for select to authenticated
  using ((select public.is_platform_admin()) or public.has_site_role(site_id, '{yonetici}'));

drop policy "borç görme" on public.dues;
create policy "borç görme" on public.dues
  for select to authenticated
  using ((select public.is_platform_admin()) or public.has_site_role(site_id, '{yonetici}'));

drop policy "ödeme görme" on public.payments;
create policy "ödeme görme" on public.payments
  for select to authenticated
  using ((select public.is_platform_admin()) or public.has_site_role(site_id, '{yonetici}'));

-- "Ödeme yaptım" bildirimi ve dekont kuralları
drop policy if exists "dekont yükleme" on storage.objects;
drop policy if exists "dekont görme" on storage.objects;
drop function public.can_upload_receipt(text);
drop function public.can_read_receipt(text);
drop function public.receipt_path_parts(text);
drop function public.reject_payment_notice(uuid, text);
drop function public.record_payment(uuid, numeric, date, text, uuid);
drop table public.payment_notices;
drop type public.notice_status;
drop function public.is_unit_resident(uuid);

-- Ödeme kaydı (bildirim bağlantısı olmadan)
create function public.record_payment(p_unit_id uuid, p_amount numeric, p_paid_on date, p_note text default null)
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
  values (p_unit_id, v_site, round(p_amount, 2), p_paid_on, 'havale', nullif(trim(p_note), ''))
  returning id into v_id;
  return v_id;
end;
$$;

revoke execute on function public.record_payment(uuid, numeric, date, text) from public, anon;
grant execute on function public.record_payment(uuid, numeric, date, text) to authenticated;

-- Aktif "sakin" üyelikleri kapatılır; bundan sonra aktif sakin üyeliği olamaz
update public.memberships set ended_on = greatest(started_on, current_date)
where role = 'sakin' and ended_on is null;
alter table public.memberships add constraint memberships_no_active_resident check (role <> 'sakin' or ended_on is not null);

drop policy "site yöneticisi üyelik yönetimi" on public.memberships;
create policy "site yöneticisi üyelik yönetimi" on public.memberships
  for all to authenticated
  using (public.has_site_role(site_id, '{yonetici}') and role = 'danisma')
  with check (public.has_site_role(site_id, '{yonetici}') and role = 'danisma');
