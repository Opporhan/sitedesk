-- Davetsiz başlangıç (kullanıcı kararı 12.10.2026; uygulama ücretsiz):
-- A) Herkes kendi sitesini açabilir: kayıtlı (giriş yapmış) her kullanıcı create_site ile site açar ve o sitenin yöneticisi olur.
-- B) Sakin site koduyla katılır: her sitenin kısa bir kodu var (join_code); sakin kodu + dairesini seçip istek gönderir
--    (request_join), sitenin yöneticisi onaylar ya da reddeder (decide_join). Onayda kişi rehbere ve daireye eklenir, hesabına bağlanır.
--    Güvenlik yöneticinin onayında: onaylanmayan kimse sitenin hiçbir bilgisini göremez. Danışma yine davetle eklenir.
set local lock_timeout = '15s';
set local statement_timeout = '60s';

-- Site kodu: 6 karakter, karışmayan harf/rakamlar (0/O, 1/I yok)
create function public.new_join_code()
returns text language plpgsql volatile set search_path = ''
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text;
begin
  loop
    v_code := (select string_agg(substr(v_alphabet, 1 + (get_byte(extensions.gen_random_bytes(1), 0) % length(v_alphabet)), 1), '')
               from generate_series(1, 6));
    exit when not exists (select 1 from public.sites s where s.join_code = v_code);
  end loop;
  return v_code;
end;
$$;
revoke execute on function public.new_join_code() from public, anon;
grant execute on function public.new_join_code() to authenticated; -- sites.join_code varsayılanı için (sadece rastgele kod üretir)

alter table public.sites add column join_code text;
update public.sites set join_code = public.new_join_code() where join_code is null;
alter table public.sites alter column join_code set not null;
alter table public.sites alter column join_code set default public.new_join_code();
create unique index sites_join_code on public.sites (join_code);

-- Yönetici kodu yeniler (eski kod artık çalışmaz)
create function public.renew_join_code(p_site_id uuid)
returns text language plpgsql security definer set search_path = ''
as $$
declare v_code text := public.new_join_code();
begin
  if not public.has_site_role(p_site_id, '{yonetici}') then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  update public.sites set join_code = v_code where id = p_site_id;
  return v_code;
end;
$$;
revoke execute on function public.renew_join_code(uuid) from public, anon;
grant execute on function public.renew_join_code(uuid) to authenticated;

-- Katılma istekleri
create table public.join_requests (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  unit_id uuid not null,
  user_id uuid references auth.users (id) on delete cascade,
  full_name text not null check (length(trim(full_name)) between 3 and 100),
  phone text not null check (phone ~ '^90[0-9]{10}$'),
  relation text not null check (relation in ('malik', 'kiraci')),
  status text not null default 'bekliyor' check (status in ('bekliyor', 'onaylandi', 'reddedildi')),
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by uuid references auth.users (id) on delete set null,
  foreign key (unit_id, site_id) references public.units (id, site_id) on delete restrict
);
create unique index join_requests_pending on public.join_requests (user_id, unit_id) where status = 'bekliyor';
create index join_requests_site on public.join_requests (site_id, status);
alter table public.join_requests enable row level security;
revoke all on public.join_requests from anon, authenticated;
grant select on public.join_requests to authenticated;
create policy "katılma isteği görme" on public.join_requests for select to authenticated
  using (user_id = (select auth.uid()) or site_id in (select public.my_site_ids('{yonetici}')));
create trigger audit after insert or update or delete on public.join_requests for each row execute function public.write_audit();

-- Koda göre site ve daireleri (katılmak isteyen, dairesini seçebilsin). Kod yanlışsa boş döner.
create function public.site_by_code(p_code text)
returns jsonb language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'site_id', s.id, 'name', s.name, 'type', s.type,
    'units', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'block', b.name, 'no', u.no) order by b.name, u.no)
                       from public.units u join public.blocks b on b.id = u.block_id where u.site_id = s.id), '[]'::jsonb))
  from public.sites s
  where s.join_code = upper(trim(p_code)) and s.active and (select auth.uid()) is not null
$$;
revoke execute on function public.site_by_code(text) from public, anon;
grant execute on function public.site_by_code(text) to authenticated;

-- Katılma isteği gönder (telefonla giriş yapan hesap; günde en fazla 5 istek)
create function public.request_join(p_code text, p_unit_id uuid, p_full_name text, p_relation text)
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
revoke execute on function public.request_join(text, uuid, text, text) from public, anon;
grant execute on function public.request_join(text, uuid, text, text) to authenticated;

-- Yönetici onaylar ya da reddeder. Onayda: aynı sitede aynı telefonlu rehber kaydı varsa ona, yoksa yeni kayda bağlanır.
create function public.decide_join(p_request_id uuid, p_approve boolean)
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
revoke execute on function public.decide_join(uuid, boolean) from public, anon;
grant execute on function public.decide_join(uuid, boolean) to authenticated;

-- A) Kayıtlı her kullanıcı kendi sitesini açabilir (o sitenin yöneticisi olur); günde en fazla 3 site
create or replace function public.create_site(p_name text, p_type public.site_type, p_address text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
  v_admin boolean := public.is_platform_admin();
begin
  if auth.uid() is null then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if length(trim(coalesce(p_name, ''))) < 2 then raise exception 'Site adını yazın' using errcode = '22023'; end if;
  if not v_admin and (select count(*) from public.sites where created_by = auth.uid() and created_at > now() - interval '1 day') >= 3 then
    raise exception 'Bugün çok fazla site açtınız' using errcode = 'SD050';
  end if;
  insert into public.sites (name, type, address) values (left(trim(p_name), 80), p_type, nullif(left(trim(coalesce(p_address, '')), 200), ''))
  returning id into v_id;
  if not v_admin then
    insert into public.profiles (user_id, full_name) values (auth.uid(), '') on conflict (user_id) do nothing;
    insert into public.memberships (user_id, site_id, role) values (auth.uid(), v_id, 'yonetici');
    perform public.notify_users((select array_agg(user_id) from public.platform_admins), 'Yeni site açıldı',
      left(trim(p_name), 80) || ' · ' || coalesce(nullif(public.my_name(), ''), 'Yeni yönetici'), '/');
  end if;
  return v_id;
end;
$$;

-- Bağlamda: bekleyen katılma isteklerim (rolü olmayan kişi "isteğiniz bekliyor" görsün)
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
                                    where r.site_id = s.id and r.user_id = (select auth.uid())))), '[]'::jsonb),
    'pending_joins', coalesce((select jsonb_agg(jsonb_build_object('site_name', s.name, 'label', public.unit_label(j.unit_id)) order by j.created_at)
                               from public.join_requests j join public.sites s on s.id = j.site_id
                               where j.user_id = (select auth.uid()) and j.status = 'bekliyor'), '[]'::jsonb)
  )
$$;
