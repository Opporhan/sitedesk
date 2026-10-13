-- Adım 8: güvenlik denetimi sonrası sıkılaştırma + temizlik ve sağlık kontrolü için sunucu fonksiyonları
-- • Uygulamanın hiç kullanmadığı doğrudan yazma yetkileri kaldırıldı (sakin rehberi, üyelik, profil telefonu, kayıt sahibi alanları).
--   Önce: yönetici sakin kaydına başka bir hesabı bağlayıp o kişinin profilini görebiliyordu; danışma üyeliğini başka kişiye çevirebiliyordu.
-- • Profil (ad, telefon, resim) görme daraltıldı: sakin, aynı sitedeki BAŞKA dairelerin sakinlerinin telefonunu göremez.
--   Görür: kendisi, sistem yöneticisi, sitenin yönetici/danışması (herkesi), sakin → sitenin görevlileri ve kendi dairesindekiler.
-- • Taşınmış sakin sitenin bilgisini görmez.
-- • Dosya deposuna sınırsız yükleme kapatıldı: kayıt başına en fazla 3, profil resmi klasöründe en fazla 3 dosya.
-- • Kayıt dosyasının türü ve boyutu telefonun söylediğinden değil, depodaki gerçek dosyadan alınır.
-- • Sunucu işleri (sadece gizli anahtarla): eski video ve sahipsiz dosya listesi, sağlık raporu, bildirim gönderimi.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

-- 1) Doğrudan yazma yetkileri: sadece uygulamanın gerçekten kullandığı kolonlar
revoke insert, update, delete on public.residents from authenticated;
drop policy "sakin ekleme" on public.residents;
drop policy "sakin düzenleme" on public.residents;
drop policy "sakin silme" on public.residents;

revoke insert, update on public.memberships from authenticated;
grant update (ended_on) on public.memberships to authenticated;
drop policy "üyelik ekleme" on public.memberships;

revoke update on public.profiles from authenticated;
grant update (full_name) on public.profiles to authenticated;

revoke insert, update on public.blocks from authenticated;
grant insert (site_id, name) on public.blocks to authenticated;
grant update (name) on public.blocks to authenticated;

revoke insert, update on public.units from authenticated;
grant insert (site_id, block_id, no, type) on public.units to authenticated;
grant update (block_id, no, type) on public.units to authenticated;

revoke insert, update on public.sites from authenticated;
grant insert (name, type, address) on public.sites to authenticated;
grant update (name, type, address, active, paid_until, video_keep_months) on public.sites to authenticated;

-- 2) Profil görme
create or replace function public.can_see_user(p_user uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select p_user = (select auth.uid())
      or public.is_platform_admin()
      -- ben görevliyim, o bu sitede (görevli ya da sakin)
      or exists (select 1 from public.user_site_ids(p_user) a where a in (select public.my_site_ids('{yonetici,danisma}')))
      -- o görevli, ben bu sitedeyim
      or exists (select 1 from public.memberships m join public.sites s on s.id = m.site_id
                 where m.user_id = p_user and m.ended_on is null and s.active
                   and m.site_id in (select public.user_site_ids((select auth.uid()))))
      -- aynı dairenin sakinleriyiz
      or exists (select 1 from public.unit_residents ur join public.residents r on r.id = ur.resident_id
                 where r.user_id = p_user and ur.ended_on is null and ur.unit_id in (select public.my_unit_ids()))
$$;

-- 3) Site görme: sakin sadece oturduğu sürece
drop policy "site görme" on public.sites;
create policy "site görme" on public.sites for select to authenticated using (
  (select public.is_platform_admin()) or public.is_site_member(id)
  or exists (select 1 from public.residents r join public.unit_residents ur on ur.resident_id = r.id and ur.ended_on is null
             where r.site_id = sites.id and r.user_id = (select auth.uid()))
);

-- 4) Depoya yükleme sınırı (dosyalar kayda bağlanmadan önce de sayılır)
create function public.storage_folder_count(p_bucket text, p_prefix text)
returns int language sql stable security definer set search_path = ''
as $$ select count(*)::int from storage.objects where bucket_id = p_bucket and name like p_prefix || '%' $$;
revoke execute on function public.storage_folder_count(text, text) from public, anon;
grant execute on function public.storage_folder_count(text, text) to authenticated;

drop policy "kayıt dosyası yükleme" on storage.objects;
create policy "kayıt dosyası yükleme" on storage.objects for insert to authenticated with check (
  bucket_id = 'kayitlar'
  and public.ticket_role(public.storage_ticket_id(name)) is not null
  and exists (select 1 from public.tickets t where t.id = public.storage_ticket_id(objects.name)
              and split_part(objects.name, '/', 1) = t.site_id::text and t.status <> 'tamamlandi')
  and public.storage_folder_count('kayitlar', split_part(name, '/', 1) || '/' || split_part(name, '/', 2) || '/') < 3
);
drop policy "profil resmi yükleme" on storage.objects;
create policy "profil resmi yükleme" on storage.objects for insert to authenticated with check (
  bucket_id = 'profil' and public.storage_owner_id(name) = (select auth.uid())
  and public.storage_folder_count('profil', (select auth.uid())::text || '/') < 3
);

-- 5) Kayıt dosyası: tür ve boyut depodaki gerçek dosyadan
create or replace function public.add_ticket_media(p_ticket_id uuid, p_path text, p_kind text, p_size integer, p_duration_ms integer)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_t public.tickets;
  v_photos int;
  v_videos int;
  v_mime text;
  v_size bigint;
  v_kind text;
begin
  select * into v_t from public.tickets where id = p_ticket_id;
  if v_t.id is null or public.ticket_role(p_ticket_id) is null then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if p_path not like v_t.site_id || '/' || v_t.id || '/%' then raise exception 'Dosya yolu hatalı' using errcode = '22023'; end if;
  if exists (select 1 from public.ticket_media where path = p_path) then return; end if; -- tekrar gönderim
  if v_t.status = 'tamamlandi' then raise exception 'Tamamlanmış kayda dosya eklenemez' using errcode = '22023'; end if;
  select o.metadata ->> 'mimetype', (o.metadata ->> 'size')::bigint into v_mime, v_size
  from storage.objects o where o.bucket_id = 'kayitlar' and o.name = p_path;
  if not found then raise exception 'Dosya yüklenmemiş' using errcode = '22023'; end if;
  v_kind := case when v_mime like 'video/%' then 'video' when v_mime like 'image/%' then 'foto' else p_kind end;
  if v_kind is distinct from p_kind then raise exception 'Dosya türü uyuşmuyor' using errcode = '22023'; end if;
  if v_kind = 'foto' and coalesce(v_size, p_size) > 10485760 then raise exception 'Fotoğraf çok büyük' using errcode = '22023'; end if;
  select count(*) filter (where kind = 'foto'), count(*) filter (where kind = 'video') into v_photos, v_videos
  from public.ticket_media where ticket_id = p_ticket_id;
  if (v_kind = 'foto' and (v_photos >= 3 or v_videos > 0)) or (v_kind = 'video' and (v_videos >= 1 or v_photos > 0)) then
    raise exception 'En fazla 3 fotoğraf ya da 1 video eklenebilir' using errcode = 'SD011';
  end if;
  insert into public.ticket_media (ticket_id, site_id, kind, path, size_bytes, duration_ms)
  values (p_ticket_id, v_t.site_id, v_kind, p_path, coalesce(v_size, p_size), p_duration_ms);
end;
$$;

-- 6) Sunucu işleri (sadece gizli anahtar; uygulama çağıramaz)
-- Silinecek dosyalar: tamamlanmış kaydın videosu (sitenin saklama süresi dolunca) + hiçbir yere bağlanmamış 1 günden eski dosyalar
create function public.files_to_purge()
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
$$;

create function public.mark_media_deleted(p_paths text[])
returns int language sql security definer set search_path = ''
as $$
  with u as (update public.ticket_media set deleted_at = now() where path = any (p_paths) and deleted_at is null returning 1)
  select count(*)::int from u
$$;

-- Sağlık raporu: zamanlanmış iş hataları, eksik iş, bildirim servisi hataları; geçersiz telefon kayıtları temizlenir
create function public.health_report()
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_removed int;
begin
  -- Expo "DeviceNotRegistered" dediği telefonlar (uygulama silinmiş) kayıttan çıkar
  begin
    with bad as (
      select distinct d -> 'details' ->> 'expoPushToken' as token
      from net._http_response r, jsonb_array_elements(r.content::jsonb -> 'data') d
      where r.created > now() - interval '1 day' and r.status_code = 200 and r.content like '{"data":[%'
        and d -> 'details' ->> 'error' = 'DeviceNotRegistered'
    ), del as (delete from public.push_tokens t using bad where t.token = bad.token returning 1)
    select count(*) into v_removed from del;
  exception when others then
    v_removed := -1; -- okunamayan cevap; rapor yine döner
  end;

  return jsonb_build_object(
    'cron_failed', coalesce((select jsonb_agg(distinct j.jobname) from cron.job_run_details d join cron.job j on j.jobid = d.jobid
                             where d.status = 'failed' and d.start_time > now() - interval '2 days'), '[]'::jsonb),
    'cron_missing', coalesce((select jsonb_agg(x) from unnest(array['ziyaretci-temizlik']) x
                              where not exists (select 1 from cron.job j where j.jobname = x and j.active)), '[]'::jsonb),
    'push_failed', (select count(*) from net._http_response r where r.created > now() - interval '1 day'
                    and (r.status_code is null or r.status_code >= 400)),
    'push_tokens_removed', v_removed
  );
end;
$$;

revoke execute on function public.files_to_purge(), public.mark_media_deleted(text[]), public.health_report() from public, anon, authenticated;
grant execute on function public.files_to_purge(), public.mark_media_deleted(text[]), public.health_report() to service_role;
grant execute on function public.notify_users(uuid[], text, text, text) to service_role;
