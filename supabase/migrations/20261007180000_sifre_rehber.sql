-- Mağaza öncesi düzeltmeler (kullanıcı onayı 07.10.2026)
-- • Şifre yenileme: yönetici, şifresini unutan kişiye WhatsApp'tan "şifre yenileme" bağlantısı/kodu gönderir (SMS yok).
--   Davetle aynı kod sistemi (invites, role = 'sifre', 24 saat, tek kullanımlık). Yeni şifreyi sunucu yazar (/api/sifre).
--   Kim kimin için: sakin ve danışma → sitenin yöneticisi; yönetici → sistem yöneticisi. Kişi başka sitelerde de varsa
--   (o sitelerin yöneticisi değilse) sadece sistem yöneticisi yenileyebilir — bir yönetici başka sitedeki hesabı ele geçiremesin.
-- • Sakin rehberi: yönetici sakini davet ettiği anda kişi daireye "uygulamada değil" olarak eklenir; danışma arayabilir,
--   WhatsApp'tan haber verebilir. Daveti kabul edince aynı kayıt hesabına bağlanır.
-- • Sakin bilgisi düzeltme (update_resident): ad her zaman; telefon sadece uygulama hesabı yoksa (giriş numarası değişmesin).
-- • my_context: sitenin türü (villa / apartman) — ekranlar "villa" ya da "daire" der.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

alter table public.invites drop constraint invites_role_check;
alter table public.invites add constraint invites_role_check check (role in ('sakin', 'danisma', 'yonetici', 'sifre'));

-- Sakin daveti: kişi davetle birlikte rehbere ve daireye eklenir
create or replace function public.create_invite(p_site_id uuid, p_role text, p_full_name text, p_phone text, p_unit_id uuid default null, p_relation text default null)
returns table (code text, token text, expires_at timestamptz)
language plpgsql security definer set search_path = ''
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text;
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_expires timestamptz := now() + interval '7 days';
  v_res uuid;
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
  if p_role = 'sakin' then
    select id into v_res from public.residents where site_id = p_site_id and phone = p_phone;
    if v_res is null then
      insert into public.residents (site_id, full_name, phone) values (p_site_id, trim(p_full_name), p_phone) returning id into v_res;
    end if;
    insert into public.unit_residents (site_id, unit_id, resident_id, relation)
    values (p_site_id, p_unit_id, v_res, coalesce(p_relation, 'malik'))
    on conflict (unit_id, resident_id) where ended_on is null do nothing;
  end if;
  return query select v_code, v_token, v_expires;
end;
$$;

-- Şifre yenileme kodu
create function public.create_password_reset(p_site_id uuid, p_phone text)
returns table (code text, token text, expires_at timestamptz, full_name text)
language plpgsql security definer set search_path = ''
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_user uuid;
  v_name text;
  v_role text;
  v_code text;
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_expires timestamptz := now() + interval '24 hours';
begin
  select u.id into v_user from auth.users u where u.email = public.login_email(p_phone);
  if v_user is null then raise exception 'Bu numarayla uygulama hesabı yok; davet gönderin' using errcode = '22023'; end if;
  if exists (select 1 from public.platform_admins where user_id = v_user) then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;

  -- Kişinin bu sitedeki rolü
  if exists (select 1 from public.memberships where user_id = v_user and site_id = p_site_id and role = 'yonetici' and ended_on is null) then v_role := 'yonetici';
  elsif exists (select 1 from public.memberships where user_id = v_user and site_id = p_site_id and role = 'danisma' and ended_on is null) then v_role := 'danisma';
  elsif exists (select 1 from public.residents r join public.unit_residents ur on ur.resident_id = r.id and ur.ended_on is null
                where r.user_id = v_user and r.site_id = p_site_id) then v_role := 'sakin';
  end if;
  if v_role is null then raise exception 'Bu kişi bu sitede kayıtlı değil' using errcode = '22023'; end if;

  if not public.is_platform_admin() then
    if v_role = 'yonetici' or not public.has_site_role(p_site_id, '{yonetici}') then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
    -- Kişinin bulunduğu her sitede yönetici olmalı (başka sitedeki hesabı ele geçiremesin)
    if exists (select 1 from public.user_site_ids(v_user) s where not public.has_site_role(s, '{yonetici}')) then
      raise exception 'Bu kişi başka sitelerde de kayıtlı; şifresini sistem yöneticisi yenileyebilir' using errcode = '42501';
    end if;
  end if;

  select coalesce(nullif(p.full_name, ''), 'Kullanıcı') into v_name from public.profiles p where p.user_id = v_user;
  update public.invites i set cancelled_at = now() where i.phone = p_phone and i.role = 'sifre' and i.used_at is null and i.cancelled_at is null;
  loop
    v_code := (select string_agg(substr(v_alphabet, 1 + (get_byte(extensions.gen_random_bytes(1), 0) % length(v_alphabet)), 1), '')
               from generate_series(1, 8));
    exit when not exists (select 1 from public.invites i where i.code = v_code);
  end loop;
  insert into public.invites (site_id, role, full_name, phone, code, token, expires_at)
  values (p_site_id, 'sifre', coalesce(v_name, 'Kullanıcı'), p_phone, v_code, v_token, v_expires);
  return query select v_code, v_token, v_expires, coalesce(v_name, 'Kullanıcı');
end;
$$;
revoke execute on function public.create_password_reset(uuid, text) from public, anon;
grant execute on function public.create_password_reset(uuid, text) to authenticated;

-- Şifre kodu davet gibi kabul edilemez; iptal: sitenin yöneticisi
create or replace function public.accept_invite(p_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_inv public.invites;
  v_uid uuid := auth.uid();
  v_res uuid;
begin
  select * into v_inv from public.invites where code = upper(trim(p_key)) or token = trim(p_key) for update;
  if not found or v_inv.role = 'sifre' or v_inv.used_at is not null or v_inv.cancelled_at is not null or v_inv.expires_at <= now()
     or not (select active from public.sites where id = v_inv.site_id) then
    raise exception 'Davet geçersiz veya süresi dolmuş' using errcode = '22023';
  end if;
  if v_uid is null or public.my_phone() is distinct from v_inv.phone then
    raise exception 'Bu davet başka bir telefon numarası için' using errcode = '42501';
  end if;
  insert into public.profiles (user_id, full_name, phone) values (v_uid, v_inv.full_name, v_inv.phone)
  on conflict (user_id) do update set full_name = coalesce(nullif(public.profiles.full_name, ''), excluded.full_name),
                                      phone = coalesce(public.profiles.phone, excluded.phone);
  if v_inv.role = 'sakin' then
    select id into v_res from public.residents where site_id = v_inv.site_id and phone = v_inv.phone;
    if v_res is null then
      insert into public.residents (site_id, full_name, phone, user_id) values (v_inv.site_id, v_inv.full_name, v_inv.phone, v_uid) returning id into v_res;
    else
      update public.residents set user_id = v_uid where id = v_res;
    end if;
    insert into public.unit_residents (site_id, unit_id, resident_id, relation)
    values (v_inv.site_id, v_inv.unit_id, v_res, v_inv.relation)
    on conflict (unit_id, resident_id) where ended_on is null do nothing;
  else
    insert into public.memberships (user_id, site_id, role) values (v_uid, v_inv.site_id, v_inv.role::public.site_role)
    on conflict (user_id, site_id, role) where ended_on is null do nothing;
  end if;
  update public.invites set used_at = now(), used_by = v_uid where id = v_inv.id;
  return jsonb_build_object('role', v_inv.role, 'site_id', v_inv.site_id);
end;
$$;

-- Sakin bilgisini düzelt (yönetici)
create function public.update_resident(p_resident_id uuid, p_full_name text, p_phone text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_r public.residents;
begin
  select * into v_r from public.residents where id = p_resident_id;
  if v_r.id is null or not public.has_site_role(v_r.site_id, '{yonetici}') then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if length(trim(coalesce(p_full_name, ''))) < 3 then raise exception 'Adı ve soyadı yazın' using errcode = '22023'; end if;
  if v_r.user_id is not null and p_phone is distinct from v_r.phone then
    raise exception 'Uygulama hesabı olan kişinin telefonu değiştirilemez' using errcode = 'SD020';
  end if;
  update public.residents set full_name = left(trim(p_full_name), 100), phone = p_phone where id = p_resident_id;
  -- Bekleyen davetteki ad ve telefon da düzelsin
  update public.invites set full_name = left(trim(p_full_name), 100), phone = coalesce(p_phone, phone)
  where site_id = v_r.site_id and phone = v_r.phone and role = 'sakin' and used_at is null and cancelled_at is null and expires_at > now();
end;
$$;
revoke execute on function public.update_resident(uuid, text, text) from public, anon;
grant execute on function public.update_resident(uuid, text, text) to authenticated;

-- Rol bilgisine sitenin türü eklenir
create or replace function public.my_context()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'platform_admin', public.is_platform_admin(),
    'full_name', (select full_name from public.profiles where user_id = (select auth.uid())),
    'staff', coalesce((select jsonb_agg(jsonb_build_object('role', m.role, 'site_id', m.site_id, 'site_name', s.name, 'site_type', s.type) order by s.name)
                       from public.memberships m join public.sites s on s.id = m.site_id
                       where m.user_id = (select auth.uid()) and m.ended_on is null and s.active), '[]'::jsonb),
    'units', coalesce((select jsonb_agg(jsonb_build_object('unit_id', u.id, 'site_id', s.id, 'site_name', s.name, 'site_type', s.type,
                                                           'label', b.name || '-' || u.no, 'type', u.type, 'relation', ur.relation)
                                        order by s.name, b.name, u.no)
                       from public.residents r
                       join public.unit_residents ur on ur.resident_id = r.id and ur.ended_on is null
                       join public.units u on u.id = ur.unit_id join public.blocks b on b.id = u.block_id
                       join public.sites s on s.id = r.site_id
                       where r.user_id = (select auth.uid()) and s.active), '[]'::jsonb),
    'closed_sites', coalesce((select jsonb_agg(distinct s.name) from public.sites s where not s.active and (
                         exists (select 1 from public.memberships m where m.site_id = s.id and m.user_id = (select auth.uid()) and m.ended_on is null)
                         or exists (select 1 from public.residents r join public.unit_residents ur on ur.resident_id = r.id and ur.ended_on is null
                                    where r.site_id = s.id and r.user_id = (select auth.uid())))), '[]'::jsonb)
  )
$$;

-- Sunucu (şifre yenileme) hesabı telefondan bulur
grant execute on function public.find_user_id_by_email(text) to service_role;

-- Davet listesi: yönetici sakin/danışma davetlerini ve kendi açtığı şifre kodlarını görür; yönetici davetlerini ve
-- sistem yöneticisinin açtığı şifre kodlarını görmez (kod başkasının hesabına girmek için kullanılamasın)
drop policy "davet görme" on public.invites;
create policy "davet görme" on public.invites for select to authenticated using (
  (select public.is_platform_admin())
  or (site_id in (select public.my_site_ids('{yonetici}')) and (role in ('sakin', 'danisma') or created_by = (select auth.uid())))
);
