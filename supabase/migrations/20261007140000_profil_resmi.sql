-- Profil resmi ve davet yetkisi (kullanıcı kararı, 07.10.2026)
-- • Davet sadece yönetimde: danışma artık sakin davet edemez (yönetici sakin ve danışma; sistem yöneticisi yönetici davet eder).
-- • Herkes kendi profil resmini yükler. Herkese kapalı "profil" deposu, yol {user_id}/{dosya}.jpg (telefonda kare kırpılır, küçültülür).
--   Resmi kim görür: kişinin kendisi, sistem yöneticisi ve aynı (aktif) sitede bulunan kişiler (yönetici, danışma, sakin).
--   Aynı kural profil bilgisine (ad, telefon) de uygulanır.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

-- ---------- Davet: sadece yönetim ----------
create or replace function public.create_invite(p_site_id uuid, p_role text, p_full_name text, p_phone text, p_unit_id uuid default null, p_relation text default null)
returns table (code text, token text, expires_at timestamptz)
language plpgsql security definer set search_path = ''
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text;
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_expires timestamptz := now() + interval '7 days';
begin
  if not (case p_role
            when 'sakin' then public.has_site_role(p_site_id, '{yonetici}')
            when 'danisma' then public.has_site_role(p_site_id, '{yonetici}')
            when 'yonetici' then public.is_platform_admin()
            else false end) then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if p_role = 'sakin' and not exists (select 1 from public.units where id = p_unit_id and site_id = p_site_id) then
    raise exception 'Daire bu sitede değil' using errcode = '22023';
  end if;
  update public.invites i set cancelled_at = now()
  where i.site_id = p_site_id and i.phone = p_phone and i.role = p_role and i.unit_id is not distinct from p_unit_id
    and i.used_at is null and i.cancelled_at is null;
  loop
    v_code := (select string_agg(substr(v_alphabet, 1 + (get_byte(extensions.gen_random_bytes(1), 0) % length(v_alphabet)), 1), '')
               from generate_series(1, 8));
    exit when not exists (select 1 from public.invites i where i.code = v_code);
  end loop;
  insert into public.invites (site_id, role, unit_id, relation, full_name, phone, code, token, expires_at)
  values (p_site_id, p_role, case when p_role = 'sakin' then p_unit_id end, case when p_role = 'sakin' then coalesce(p_relation, 'malik') end,
          trim(p_full_name), p_phone, v_code, v_token, v_expires);
  return query select v_code, v_token, v_expires;
end;
$$;

create or replace function public.cancel_invite(p_invite_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_inv public.invites;
begin
  select * into v_inv from public.invites where id = p_invite_id;
  if not found or not (case when v_inv.role = 'yonetici' then public.is_platform_admin() else public.has_site_role(v_inv.site_id, '{yonetici}') end) then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  update public.invites set cancelled_at = now() where id = p_invite_id and used_at is null and cancelled_at is null;
end;
$$;

-- Davetleri sadece yönetim görür
alter policy "davet görme" on public.invites using (site_id in (select public.my_site_ids('{yonetici}')));

-- ---------- Profil resmi ----------
alter table public.profiles add column avatar_path text check (avatar_path is null or avatar_path ~ '^[0-9a-f-]{36}/[A-Za-z0-9._-]+\.jpg$');

-- Kişinin bulunduğu aktif siteler (üyelik ya da aktif daire bağlantısı)
create function public.user_site_ids(p_user uuid)
returns setof uuid language sql stable security definer set search_path = ''
as $$
  select m.site_id from public.memberships m join public.sites s on s.id = m.site_id
  where m.user_id = p_user and m.ended_on is null and s.active
  union
  select ur.site_id from public.unit_residents ur join public.residents r on r.id = ur.resident_id join public.sites s on s.id = ur.site_id
  where r.user_id = p_user and ur.ended_on is null and s.active
$$;
revoke execute on function public.user_site_ids(uuid) from public, anon, authenticated;

-- Bu kişinin profilini (ad, telefon, resim) görebilir miyim?
create function public.can_see_user(p_user uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select p_user = (select auth.uid())
      or public.is_platform_admin()
      or exists (select 1 from public.user_site_ids(p_user) a join public.user_site_ids((select auth.uid())) b on a = b)
$$;
revoke execute on function public.can_see_user(uuid) from public, anon;
grant execute on function public.can_see_user(uuid) to authenticated;

alter policy "profil görme" on public.profiles using (public.can_see_user(user_id));

-- Resmi kaydet (dosya depoya yüklendikten sonra) ya da kaldır (null)
create function public.set_my_avatar(p_path text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if p_path is not null and (p_path not like auth.uid()::text || '/%'
     or not exists (select 1 from storage.objects where bucket_id = 'profil' and name = p_path)) then
    raise exception 'Dosya bulunamadı' using errcode = '22023';
  end if;
  update public.profiles set avatar_path = p_path where user_id = auth.uid();
end;
$$;
revoke execute on function public.set_my_avatar(text) from public, anon;
grant execute on function public.set_my_avatar(text) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profil', 'profil', false, 2097152, array['image/jpeg'])
on conflict (id) do nothing;

-- Yol: {user_id}/{dosya}. Yükleme ve silme sadece kendi klasörüne; görme can_see_user kuralıyla.
create function public.storage_owner_id(p_name text)
returns uuid language sql immutable set search_path = ''
as $$ select case when split_part(p_name, '/', 1) ~ '^[0-9a-f-]{36}$' then split_part(p_name, '/', 1)::uuid end $$;

create policy "profil resmi görme" on storage.objects for select to authenticated
  using (bucket_id = 'profil' and public.can_see_user(public.storage_owner_id(name)));
create policy "profil resmi yükleme" on storage.objects for insert to authenticated
  with check (bucket_id = 'profil' and public.storage_owner_id(name) = (select auth.uid()));
create policy "profil resmi silme" on storage.objects for delete to authenticated
  using (bucket_id = 'profil' and public.storage_owner_id(name) = (select auth.uid()));

-- ---------- Danışma da kaydın durumunu değiştirir (kullanıcı kararı, 07.10.2026) ----------
create or replace function public.set_ticket_status(p_ticket_id uuid, p_status text, p_body text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
  v_role text := public.ticket_role(p_ticket_id);
begin
  if v_role is null or v_role not in ('yonetici', 'danisma') then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if p_status not in ('alindi', 'inceleniyor', 'yapiliyor', 'tamamlandi') then raise exception 'Durum hatalı' using errcode = '22023'; end if;
  update public.tickets set status = p_status, updated_at = now(),
    closed_at = case when p_status = 'tamamlandi' then now() end,
    resolution = case when p_status = 'tamamlandi' then null else resolution end
  where id = p_ticket_id returning site_id into v_site;
  insert into public.ticket_events (ticket_id, site_id, kind, status, body, author_id, author_name, author_role)
  values (p_ticket_id, v_site, 'durum', p_status, nullif(left(trim(coalesce(p_body, '')), 1000), ''), auth.uid(), public.my_name(), v_role);
end;
$$;
