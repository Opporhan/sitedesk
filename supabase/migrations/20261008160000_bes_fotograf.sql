-- Kayıt başına en fazla 5 fotoğraf (kullanıcı kararı 08.10.2026; önce 3'tü). Video yine tek (30 sn), fotoğrafla birlikte olmaz.
set local lock_timeout = '15s';
set local statement_timeout = '60s';

drop policy "kayıt dosyası yükleme" on storage.objects;
create policy "kayıt dosyası yükleme" on storage.objects for insert to authenticated with check (
  bucket_id = 'kayitlar'
  and public.ticket_role(public.storage_ticket_id(name)) is not null
  and exists (select 1 from public.tickets t where t.id = public.storage_ticket_id(objects.name)
              and split_part(objects.name, '/', 1) = t.site_id::text and t.status <> 'tamamlandi')
  and public.storage_folder_count('kayitlar', split_part(name, '/', 1) || '/' || split_part(name, '/', 2) || '/') < 5
);

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
  if (v_kind = 'foto' and (v_photos >= 5 or v_videos > 0)) or (v_kind = 'video' and (v_videos >= 1 or v_photos > 0)) then
    raise exception 'En fazla 5 fotoğraf ya da 1 video eklenebilir' using errcode = 'SD011';
  end if;
  insert into public.ticket_media (ticket_id, site_id, kind, path, size_bytes, duration_ms)
  values (p_ticket_id, v_t.site_id, v_kind, p_path, coalesce(v_size, p_size), p_duration_ms);
end;
$$;
