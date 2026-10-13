-- Adım 5: site aktif/kapalı ve ödeme bitiş tarihi; sistem yöneticisi için site istatistikleri
-- • Kapalı sitede (ödeme kesildi) sistem yöneticisi dışında KİMSE hiçbir şey göremez ve yapamaz: yönetici, danışma, sakin.
--   Veriler silinmez; site yeniden açılınca her şey geri gelir. Kural veritabanında, tek yerde: has_site_role, my_site_ids, my_unit_ids.
-- • paid_until: yönetimin ödediği son gün (bilgi + ileride hatırlatma). Tarih geçince site kendiliğinden kapanmaz (kararı sistem yöneticisi verir).
-- • platform_site_stats(): her site için daire, hesap, açık kayıt sayısı ve dosya deposu kullanımı (sadece sistem yöneticisi).

set local lock_timeout = '15s';
set local statement_timeout = '60s';

alter table public.sites
  add column active boolean not null default true,
  add column paid_until date;

-- Yetkili siteler: sistem yöneticisi her site; diğerleri sadece AKTİF sitelerdeki üyelikleri
create or replace function public.has_site_role(p_site_id uuid, p_roles public.site_role[])
returns boolean language sql stable security definer set search_path = ''
as $$
  select public.is_platform_admin()
      or exists (
        select 1 from public.memberships m join public.sites s on s.id = m.site_id
        where m.user_id = (select auth.uid()) and m.site_id = p_site_id and m.role = any (p_roles) and m.ended_on is null and s.active
      );
$$;

create or replace function public.my_site_ids(p_roles public.site_role[])
returns setof uuid language sql stable security definer set search_path = ''
as $$
  select s.id from public.sites s where public.is_platform_admin()
  union
  select m.site_id from public.memberships m join public.sites s on s.id = m.site_id
  where m.user_id = (select auth.uid()) and m.role = any (p_roles) and m.ended_on is null and s.active
$$;

-- Sakinin aktif daireleri (sadece aktif sitelerde)
create function public.my_unit_ids()
returns setof uuid language sql stable security definer set search_path = ''
as $$
  select ur.unit_id from public.unit_residents ur
  join public.residents r on r.id = ur.resident_id
  join public.sites s on s.id = ur.site_id
  where r.user_id = (select auth.uid()) and ur.ended_on is null and s.active
$$;
revoke execute on function public.my_unit_ids() from public, anon;
grant execute on function public.my_unit_ids() to authenticated;

-- Sakin erişimi tek yerden (kapalı site dahil)
alter policy "blok görme" on public.blocks
  using (site_id in (select public.my_site_ids('{yonetici,danisma}'))
         or id in (select u.block_id from public.units u where u.id in (select public.my_unit_ids())));
alter policy "daire görme" on public.units
  using (site_id in (select public.my_site_ids('{yonetici,danisma}')) or id in (select public.my_unit_ids()));
alter policy "kayıt görme" on public.tickets
  using (site_id in (select public.my_site_ids('{yonetici,danisma}')) or unit_id in (select public.my_unit_ids()));

create or replace function public.ticket_role(p_ticket_id uuid)
returns text language sql stable security definer set search_path = ''
as $$
  select case
    when public.has_site_role(t.site_id, '{yonetici}') then 'yonetici'
    when public.has_site_role(t.site_id, '{danisma}') then 'danisma'
    when t.unit_id in (select public.my_unit_ids()) then 'sakin'
  end
  from public.tickets t where t.id = p_ticket_id
$$;

create or replace function public.create_ticket(p_client_id uuid, p_unit_id uuid, p_kind text, p_location text, p_title text, p_description text, p_urgent boolean)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
  v_role text;
  v_id uuid;
begin
  select id into v_id from public.tickets where client_id = p_client_id;
  if v_id is not null then
    if public.ticket_role(v_id) is null then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
    return v_id;
  end if;
  select site_id into v_site from public.units where id = p_unit_id;
  if v_site is null then raise exception 'Daire bulunamadı' using errcode = '22023'; end if;
  v_role := case
    when public.has_site_role(v_site, '{yonetici}') then 'yonetici'
    when public.has_site_role(v_site, '{danisma}') then 'danisma'
    when p_unit_id in (select public.my_unit_ids()) then 'sakin'
  end;
  if v_role is null then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if (select count(*) from public.tickets where created_by = (select auth.uid()) and created_at > now() - interval '1 day') >= 20 then
    raise exception 'Bugün çok fazla kayıt açtınız; yarın tekrar deneyin' using errcode = 'SD010';
  end if;
  insert into public.tickets (site_id, unit_id, client_id, kind, location, title, description, urgent, created_by_role)
  values (v_site, p_unit_id, p_client_id, p_kind, p_location, trim(p_title), nullif(trim(coalesce(p_description, '')), ''), coalesce(p_urgent, false), v_role)
  returning id into v_id;
  insert into public.ticket_events (ticket_id, site_id, kind, status, author_id, author_name, author_role)
  values (v_id, v_site, 'durum', 'alindi', auth.uid(), public.my_name(), v_role);
  return v_id;
end;
$$;

-- Davet kabulü kapalı sitede olmaz
create or replace function public.accept_invite(p_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_inv public.invites;
  v_uid uuid := auth.uid();
  v_res uuid;
begin
  select * into v_inv from public.invites where code = upper(trim(p_key)) or token = trim(p_key) for update;
  if not found or v_inv.used_at is not null or v_inv.cancelled_at is not null or v_inv.expires_at <= now()
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

-- Rol bilgisi: kapalı sitelerdeki roller görünmez, bunun yerine "kapalı site" listesi döner (uygulama açıklama gösterir)
create or replace function public.my_context()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'platform_admin', public.is_platform_admin(),
    'full_name', (select full_name from public.profiles where user_id = (select auth.uid())),
    'staff', coalesce((select jsonb_agg(jsonb_build_object('role', m.role, 'site_id', m.site_id, 'site_name', s.name) order by s.name)
                       from public.memberships m join public.sites s on s.id = m.site_id
                       where m.user_id = (select auth.uid()) and m.ended_on is null and s.active), '[]'::jsonb),
    'units', coalesce((select jsonb_agg(jsonb_build_object('unit_id', u.id, 'site_id', s.id, 'site_name', s.name,
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

-- Sistem yöneticisi: bütün siteler, sayılar ve dosya deposu kullanımı
create function public.platform_site_stats()
returns table (site_id uuid, name text, active boolean, paid_until date, is_demo boolean, units bigint, residents_with_app bigint,
               staff bigint, open_tickets bigint, storage_bytes bigint)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_platform_admin() then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  return query
  select s.id, s.name, s.active, s.paid_until, s.is_demo,
    (select count(*) from public.units u where u.site_id = s.id),
    (select count(distinct r.id) from public.residents r join public.unit_residents ur on ur.resident_id = r.id and ur.ended_on is null
       where r.site_id = s.id and r.user_id is not null),
    (select count(*) from public.memberships m where m.site_id = s.id and m.ended_on is null),
    (select count(*) from public.tickets t where t.site_id = s.id and t.status <> 'tamamlandi'),
    coalesce((select sum((o.metadata ->> 'size')::bigint) from storage.objects o
              where o.bucket_id = 'kayitlar' and split_part(o.name, '/', 1) = s.id::text), 0)::bigint
  from public.sites s
  order by s.is_demo, s.name;
end;
$$;
revoke execute on function public.platform_site_stats() from public, anon;
grant execute on function public.platform_site_stats() to authenticated;
