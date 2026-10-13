-- Sakin listesi dosyaları için geçici depo (kullanıcı onayı 09.10.2026): uygulama Excel/CSV/PDF dosyasını (en fazla 10 MB)
-- kapalı "listeler" deposuna yükler, sunucu okuyup hemen siler; kalan olursa gece temizliği 1 saatten eski dosyaları siler.
-- Sadece aktif yönetici ya da sistem yöneticisi, sadece kendi klasörüne ({user_id}/...) yükleyebilir; kimse okuyamaz (sunucu gizli anahtarla okur).
set local lock_timeout = '15s';
set local statement_timeout = '60s';

insert into storage.buckets (id, name, public, file_size_limit) values ('listeler', 'listeler', false, 10485760);

create policy "liste dosyası yükleme" on storage.objects for insert to authenticated with check (
  bucket_id = 'listeler'
  and public.storage_owner_id(name) = (select auth.uid())
  and ((select public.is_platform_admin()) or exists (
        select 1 from public.memberships m join public.sites s on s.id = m.site_id
        where m.user_id = (select auth.uid()) and m.role = 'yonetici' and m.ended_on is null and s.active))
  and public.storage_folder_count('listeler', (select auth.uid())::text || '/') < 5
);

create or replace function public.files_to_purge()
returns table (bucket text, path text, reason text) language sql stable security definer set search_path = ''
as $$
  select 'kayitlar', m.path, 'video'
  from public.ticket_media m join public.tickets t on t.id = m.ticket_id join public.sites s on s.id = t.site_id
  where m.kind = 'video' and m.deleted_at is null and t.status = 'tamamlandi'
    and t.closed_at < now() - make_interval(months => s.video_keep_months)
  union all
  select o.bucket_id, o.name, 'sahipsiz'
  from storage.objects o
  where o.bucket_id = 'kayitlar' and o.created_at < now() - interval '1 day'
    and not exists (select 1 from public.ticket_media m where m.path = o.name)
  union all
  select o.bucket_id, o.name, 'sahipsiz'
  from storage.objects o
  where o.bucket_id = 'profil' and o.created_at < now() - interval '1 day'
    and not exists (select 1 from public.profiles p where p.avatar_path = o.name)
  union all
  select o.bucket_id, o.name, 'gecici'
  from storage.objects o
  where o.bucket_id = 'listeler' and o.created_at < now() - interval '1 hour'
$$;
