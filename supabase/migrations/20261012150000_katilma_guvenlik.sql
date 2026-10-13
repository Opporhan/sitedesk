-- Güvenlik düzeltmeleri (kullanıcı onayı 12.10.2026):
-- 1) Telefon numarası SMS ile doğrulanmadığı için başkası, yönetimin rehbere eklediği (davet ettiği) birinin numarasıyla hesap açıp
--    site koduyla katılarak onun dairelerine bağlanabilirdi. Artık rehberdeki (henüz uygulamada olmayan) numara site koduyla katılamaz;
--    sadece kendisine gönderilen davetle girer (davet kodu kişinin WhatsApp'ına gider).
-- 2) Hesap açma sınırı: aynı internet adresinden saatte en fazla 20, toplamda saatte en fazla 500 hesap (sahte hesap yağmuruna karşı).
--    Adres saklanmaz, sadece geri çözülemeyen özeti (hash) 1 gün tutulur. /api/kayit sunucu anahtarıyla çağırır.
-- 3) Siteyi açan yöneticinin erişimini diğer yöneticiler kapatamaz (sadece sistem yöneticisi).
set local lock_timeout = '15s';
set local statement_timeout = '60s';

create or replace function public.request_join(p_code text, p_unit_id uuid, p_full_name text, p_relation text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
  v_phone text := public.my_phone();
  v_id uuid;
  v_label text;
begin
  if auth.uid() is null or v_phone is null then raise exception 'Telefon numarasıyla giriş yapın' using errcode = '42501'; end if;
  select id into v_site from public.sites where join_code = upper(trim(p_code)) and active;
  if v_site is null then raise exception 'Site kodu bulunamadı' using errcode = 'SD060'; end if;
  -- Yönetimin rehbere eklediği (davet gönderdiği) numara site koduyla katılamaz: başkası o numarayla hesap açıp yerine geçemesin
  if exists (select 1 from public.residents r where r.site_id = v_site and r.phone = v_phone and r.user_id is null) then
    raise exception 'Bu numaraya davet gönderilmiş; davetle girin' using errcode = 'SD063';
  end if;
  if not exists (select 1 from public.units where id = p_unit_id and site_id = v_site) then raise exception 'Daire bu sitede değil' using errcode = '22023'; end if;
  if p_relation not in ('malik', 'kiraci') then raise exception 'Malik/kiracı seçin' using errcode = '22023'; end if;
  if p_unit_id in (select public.my_unit_ids()) then raise exception 'Bu daireye zaten bağlısınız' using errcode = 'SD061'; end if;
  if (select count(*) from public.join_requests where user_id = auth.uid() and created_at > now() - interval '1 day') >= 5 then
    raise exception 'Bugün çok fazla istek gönderdiniz' using errcode = 'SD062';
  end if;
  select id into v_id from public.join_requests where user_id = auth.uid() and unit_id = p_unit_id and status = 'bekliyor';
  if v_id is not null then return v_id; end if; -- aynı istek tekrar gönderilmez
  insert into public.join_requests (site_id, unit_id, user_id, full_name, phone, relation)
  values (v_site, p_unit_id, auth.uid(), left(trim(p_full_name), 100), v_phone, p_relation)
  returning id into v_id;
  v_label := public.unit_label(p_unit_id);
  perform public.notify_users(public.site_manager_users(v_site), 'Katılma isteği · ' || v_label,
    left(trim(p_full_name), 100) || ' (' || case p_relation when 'kiraci' then 'kiracı' else 'malik' end || ') siteye katılmak istiyor.', '/yonetici/kisiler');
  return v_id;
end;
$$;

create or replace function public.decide_join(p_request_id uuid, p_approve boolean)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_r public.join_requests;
  v_res uuid;
  v_site_name text;
begin
  select * into v_r from public.join_requests where id = p_request_id for update;
  if v_r.id is null or not public.has_site_role(v_r.site_id, '{yonetici}') then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if v_r.status <> 'bekliyor' then return; end if;
  update public.join_requests set status = case when p_approve then 'onaylandi' else 'reddedildi' end, decided_at = now(), decided_by = auth.uid()
  where id = p_request_id;
  select name into v_site_name from public.sites where id = v_r.site_id;
  if not p_approve then
    perform public.notify_users(array[v_r.user_id], 'Katılma isteğiniz onaylanmadı', v_site_name || ' yönetimi isteğinizi onaylamadı. Bilgi için yönetiminizle görüşün.', '/');
    return;
  end if;
  if v_r.user_id is null then raise exception 'Bu hesap silinmiş' using errcode = '22023'; end if;
  insert into public.profiles (user_id, full_name, phone) values (v_r.user_id, v_r.full_name, v_r.phone)
  on conflict (user_id) do update set full_name = coalesce(nullif(public.profiles.full_name, ''), excluded.full_name),
                                      phone = coalesce(public.profiles.phone, excluded.phone);
  select id into v_res from public.residents where site_id = v_r.site_id and phone = v_r.phone and user_id is null;
  if v_res is not null then
    raise exception 'Bu kişiye davet gönderilmiş; davetle girmesi gerekiyor' using errcode = 'SD063';
  end if;
  select id into v_res from public.residents where site_id = v_r.site_id and phone = v_r.phone;
  if v_res is null then
    insert into public.residents (site_id, full_name, phone, user_id) values (v_r.site_id, v_r.full_name, v_r.phone, v_r.user_id) returning id into v_res;
  else
    update public.residents set user_id = v_r.user_id where id = v_res;
  end if;
  insert into public.unit_residents (site_id, unit_id, resident_id, relation)
  values (v_r.site_id, v_r.unit_id, v_res, v_r.relation)
  on conflict (unit_id, resident_id) where ended_on is null do nothing;
  perform public.notify_users(array[v_r.user_id], 'Siteye katıldınız', v_site_name || ' · ' || public.unit_label(v_r.unit_id) || ' için isteğiniz onaylandı.', '/');
end;
$$;

create table public.signup_attempts (
  ip_hash text not null,
  created_at timestamptz not null default now()
);
create index signup_attempts_ip on public.signup_attempts (ip_hash, created_at);
alter table public.signup_attempts enable row level security;
revoke all on public.signup_attempts from anon, authenticated;

create function public.allow_signup(p_ip_hash text)
returns boolean language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.signup_attempts where created_at < now() - interval '1 day';
  if (select count(*) from public.signup_attempts where ip_hash = p_ip_hash and created_at > now() - interval '1 hour') >= 20
     or (select count(*) from public.signup_attempts where created_at > now() - interval '1 hour') >= 500 then
    return false;
  end if;
  insert into public.signup_attempts (ip_hash) values (left(p_ip_hash, 128));
  return true;
end;
$$;
revoke execute on function public.allow_signup(text) from public, anon, authenticated;
grant execute on function public.allow_signup(text) to service_role;

drop policy "üyelik düzenleme" on public.memberships;
create policy "üyelik düzenleme" on public.memberships for update to authenticated
  using ((select public.is_platform_admin()) or (site_id in (select public.my_site_ids('{yonetici}'))
         and (role = 'danisma' or (role = 'yonetici' and user_id <> (select auth.uid())
              and user_id is distinct from (select s.created_by from public.sites s where s.id = memberships.site_id)))))
  with check ((select public.is_platform_admin()) or (site_id in (select public.my_site_ids('{yonetici}'))
         and (role = 'danisma' or (role = 'yonetici' and user_id <> (select auth.uid())
              and user_id is distinct from (select s.created_by from public.sites s where s.id = memberships.site_id)))));
