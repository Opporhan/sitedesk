-- SIFIRDAN BAŞLANGIÇ (kullanıcı kararı, 06.10.2026): aidat, ödeme, kasa, bütçe, banka, kargo, ziyaretçi, arıza, duyuru, anket,
-- toplu bildirim, paylaşım, paket, demo… her şey kaldırılır. Sadece giriş ve üç rol kalır:
--   • sites (ad, tür, adres) · memberships (yönetici / danışma) · residents (sakin: ad, telefon, uygulama hesabı)
--   • profiles · platform_admins
-- Demo siteleri, demo hesabı ve deneme sakin hesabı silinir. Eski sürüm git'te: eski-surum-2026-10-06.
-- Bu dosya uygulanmadan önce tam yedek alınır (npm run yedek).

set local lock_timeout = '15s';
set local statement_timeout = '120s';

-- 1. Zamanlanmış veritabanı işleri (aylık aidat, gecikme tazminatı, ziyaretçi temizliği)
select cron.unschedule(jobname) from cron.job;

-- 2. Dosya depolarının (belgeler, ariza; boş) kuralları. Depoların kendisi Storage API ile silinir (SQL ile silinemez).
do $$
declare p record;
begin
  for p in select policyname from pg_policies where schemaname = 'storage' and tablename = 'objects'
           and (coalesce(qual, '') || coalesce(with_check, '')) ~ '(belgeler|ariza)' loop
    execute format('drop policy %I on storage.objects', p.policyname);
  end loop;
end;
$$;

-- 3. Kalan beş tablo dışındaki her şey: görünümler, tablolar, fonksiyonlar
do $$
declare r record;
begin
  for r in select viewname from pg_views where schemaname = 'public' loop
    execute format('drop view if exists public.%I cascade', r.viewname);
  end loop;
  for r in select tablename from pg_tables where schemaname = 'public'
           and tablename not in ('sites', 'memberships', 'residents', 'profiles', 'platform_admins') loop
    execute format('drop table if exists public.%I cascade', r.tablename);
  end loop;
  -- Kurallar yeniden yazılacak: kalan tablolardaki bütün kuralları kaldır
  for r in select tablename, policyname from pg_policies where schemaname = 'public' loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
  -- Kalacak fonksiyonlar dışındakiler (bağlı tetikleyiciler de gider)
  for r in select p.oid::regprocedure as sig from pg_proc p
           where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
             and p.proname not in ('is_platform_admin', 'has_site_role', 'my_site_ids', 'is_site_member', 'find_user_id_by_email',
                                   'handle_new_user', 'sync_user_email', 'prevent_reopen', 'resident_login_email', 'resident_auth_user',
                                   'resident_account_phone', 'link_resident_account', 'unlink_resident_account', 'my_resident_summary') loop
    execute format('drop function if exists %s cascade', r.sig);
  end loop;
end;
$$;

-- 4. Demo siteleri ve hesapları (demo hesabı, deneme sakin hesabı), izleyici üyelikleri
delete from public.memberships where role not in ('yonetici', 'danisma');
delete from auth.users where email = 'demo@example.com' or email like 'sakin-%@sakin.sitedesk.invalid';
delete from public.residents where site_id in (select id from public.sites where is_demo);
delete from public.memberships where site_id in (select id from public.sites where is_demo);
delete from public.sites where is_demo;

-- 5. Kalan tabloların sade hali
alter table public.sites
  drop column if exists due_day, drop column if exists is_demo, drop column if exists late_fee_enabled,
  drop column if exists late_fee_rate, drop column if exists late_fee_since, drop column if exists setup_step, drop column if exists package;
alter table public.residents drop column if exists informed_at, drop column if exists informed_via;
alter table public.memberships add constraint memberships_role_check check (role in ('yonetici', 'danisma'));

-- Kullanılmayan türler
drop type if exists public.unit_type, public.resident_relation, public.due_status, public.payment_method,
  public.payment_status, public.cash_kind, public.ticket_status cascade;

-- 6. Sakin hesabı fonksiyonları (paket ve birim bağlantısı olmadan)
create or replace function public.resident_account_phone(p_resident_id uuid)
returns text
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_site uuid;
  v_phone text;
begin
  select site_id, phone into v_site, v_phone from public.residents where id = p_resident_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if v_phone is null then
    raise exception 'Telefonu olmayan sakine hesap açılamaz' using errcode = '22023';
  end if;
  return v_phone;
end;
$$;

-- Giriş yapan sakinin adı ve siteleri (sakin değilse boş)
create or replace function public.my_resident_summary()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select case when count(*) = 0 then null else jsonb_build_object('name', min(r.full_name), 'sites', jsonb_agg(distinct s.name)) end
  from public.residents r join public.sites s on s.id = r.site_id
  where r.user_id = (select auth.uid())
$$;

-- 7. Yetkiler ve güvenlik kuralları
revoke all on public.sites, public.memberships, public.residents, public.profiles, public.platform_admins from anon, authenticated;
grant select, insert, update on public.sites to authenticated;
grant select, insert, update on public.memberships to authenticated;
grant select, insert, update, delete on public.residents to authenticated;
grant select on public.profiles, public.platform_admins to authenticated;
grant update (full_name, phone) on public.profiles to authenticated;

-- Site: sistem yöneticisi yönetir; üyeler ve sakinler kendi sitesini görür
create policy "site görme" on public.sites for select to authenticated
  using ((select public.is_platform_admin()) or public.is_site_member(id)
         or exists (select 1 from public.residents r where r.site_id = sites.id and r.user_id = (select auth.uid())));
create policy "site ekleme" on public.sites for insert to authenticated with check ((select public.is_platform_admin()));
create policy "site düzenleme" on public.sites for update to authenticated
  using ((select public.is_platform_admin())) with check ((select public.is_platform_admin()));

-- Üyelik: kişi kendi üyeliğini, sistem yöneticisi hepsini görür ve yönetir
create policy "üyelik görme" on public.memberships for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_platform_admin()));
create policy "üyelik ekleme" on public.memberships for insert to authenticated with check ((select public.is_platform_admin()));
create policy "üyelik düzenleme" on public.memberships for update to authenticated
  using ((select public.is_platform_admin())) with check ((select public.is_platform_admin()));

-- Sakin: sistem yöneticisi yönetir; sitenin yönetici ve danışması görür; sakin kendi kaydını görür
create policy "sakin görme" on public.residents for select to authenticated
  using ((select public.is_platform_admin()) or site_id in (select public.my_site_ids('{yonetici,danisma}'))
         or user_id = (select auth.uid()));
create policy "sakin ekleme" on public.residents for insert to authenticated with check ((select public.is_platform_admin()));
create policy "sakin düzenleme" on public.residents for update to authenticated
  using ((select public.is_platform_admin())) with check ((select public.is_platform_admin()));
create policy "sakin silme" on public.residents for delete to authenticated using ((select public.is_platform_admin()));

-- Profil: kişi kendini, sistem yöneticisi herkesi görür; herkes kendi adını ve telefonunu düzenler
create policy "profil görme" on public.profiles for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_platform_admin()));
create policy "kendi profilini düzenler" on public.profiles for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "kendi kaydını görür" on public.platform_admins for select to authenticated using (user_id = (select auth.uid()));

-- Aynı sitede aynı telefon bir kişidir
create unique index if not exists residents_site_phone on public.residents (site_id, phone) where phone is not null;
