-- Arıza / talep / şikâyet / öneri kayıtları (adım 4, kullanıcı onayı 06.10.2026)
-- • Kayıt bir daireye bağlıdır (sakin kendi dairesi için açar; yer: daire içi ya da ortak alan). Danışma/yönetici sakin adına da açabilir.
-- • Durum: alindi → inceleniyor → yapiliyor → tamamlandi. Tamamlanınca sakin "çözüldü" ya da "devam ediyor" der (devam → inceleniyor).
-- • Notlar ve durum değişiklikleri zaman çizelgesine yazılır (ticket_events); herkes (sakin, danışma, yönetici) görür.
-- • Dosyalar: en fazla 3 fotoğraf YA DA 1 video (30 sn). Herkese kapalı "kayitlar" deposu, yol {site_id}/{ticket_id}/{dosya}.
-- • Görme: sakin sadece kendi (aktif) dairesinin kayıtlarını ve dosyalarını; yönetici ve danışma sadece kendi sitesininkileri.
-- • Zayıf internet: uygulama her kayda kendi kimliğini (client_id) verir; aynı kayıt tekrar gönderilirse ikinci kayıt açılmaz.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

create table public.tickets (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null,
  unit_id uuid not null,
  client_id uuid not null unique,
  kind text not null check (kind in ('ariza', 'talep', 'sikayet', 'oneri')),
  location text not null check (location in ('daire', 'ortak')),
  title text not null check (length(trim(title)) between 3 and 80),
  description text check (description is null or length(description) <= 1000),
  urgent boolean not null default false,
  status text not null default 'alindi' check (status in ('alindi', 'inceleniyor', 'yapiliyor', 'tamamlandi')),
  resolution text check (resolution in ('cozuldu', 'devam')),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_by_role text not null check (created_by_role in ('sakin', 'danisma', 'yonetici')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  closed_at timestamptz,
  foreign key (unit_id, site_id) references public.units (id, site_id) on delete restrict,
  unique (id, site_id)
);
create index on public.tickets (site_id, status, created_at);
create index on public.tickets (unit_id, created_at desc);

create table public.ticket_events (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null,
  site_id uuid not null,
  kind text not null check (kind in ('not', 'durum', 'sonuc')),
  body text check (body is null or length(body) <= 1000),
  status text,
  author_id uuid references auth.users (id) on delete set null,
  author_name text,
  author_role text not null check (author_role in ('sakin', 'danisma', 'yonetici')),
  created_at timestamptz not null default now(),
  foreign key (ticket_id, site_id) references public.tickets (id, site_id) on delete cascade
);
create index on public.ticket_events (ticket_id, created_at);

create table public.ticket_media (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null,
  site_id uuid not null,
  kind text not null check (kind in ('foto', 'video')),
  path text not null unique,
  size_bytes integer check (size_bytes > 0 and size_bytes <= 52428800),
  duration_ms integer check (duration_ms is null or duration_ms <= 31000),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz, -- video saklama süresi dolunca dosya silinir, satır kalır
  foreign key (ticket_id, site_id) references public.tickets (id, site_id) on delete cascade
);
create index on public.ticket_media (ticket_id);

-- Kişinin bu kayıttaki rolü: sakin (kaydın dairesinde aktif) / danışma / yönetici; erişimi yoksa null
create function public.ticket_role(p_ticket_id uuid)
returns text language sql stable security definer set search_path = ''
as $$
  select case
    when public.has_site_role(t.site_id, '{yonetici}') then 'yonetici'
    when public.has_site_role(t.site_id, '{danisma}') then 'danisma'
    when exists (select 1 from public.unit_residents ur join public.residents r on r.id = ur.resident_id
                 where ur.unit_id = t.unit_id and ur.ended_on is null and r.user_id = (select auth.uid())) then 'sakin'
  end
  from public.tickets t where t.id = p_ticket_id
$$;

create function public.my_name()
returns text language sql stable security definer set search_path = ''
as $$ select coalesce(nullif(full_name, ''), 'Kullanıcı') from public.profiles where user_id = (select auth.uid()) $$;

-- Kayıt aç (aynı client_id ile tekrar gelirse var olan kaydı döner)
create function public.create_ticket(p_client_id uuid, p_unit_id uuid, p_kind text, p_location text, p_title text, p_description text, p_urgent boolean)
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
    when exists (select 1 from public.unit_residents ur join public.residents r on r.id = ur.resident_id
                 where ur.unit_id = p_unit_id and ur.ended_on is null and r.user_id = (select auth.uid())) then 'sakin'
  end;
  if v_role is null then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  -- Kötüye kullanım sınırı: kişi başı günde 20 kayıt
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

-- Fotoğraf/video kaydı (dosya depoya yüklendikten sonra). En fazla 3 fotoğraf ya da 1 video; tamamlanmış kayda eklenmez.
create function public.add_ticket_media(p_ticket_id uuid, p_path text, p_kind text, p_size integer, p_duration_ms integer)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_t public.tickets;
  v_photos int;
  v_videos int;
begin
  select * into v_t from public.tickets where id = p_ticket_id;
  if v_t.id is null or public.ticket_role(p_ticket_id) is null then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if p_path not like v_t.site_id || '/' || v_t.id || '/%' then raise exception 'Dosya yolu hatalı' using errcode = '22023'; end if;
  if exists (select 1 from public.ticket_media where path = p_path) then return; end if; -- tekrar gönderim
  if v_t.status = 'tamamlandi' then raise exception 'Tamamlanmış kayda dosya eklenemez' using errcode = '22023'; end if;
  select count(*) filter (where kind = 'foto'), count(*) filter (where kind = 'video') into v_photos, v_videos
  from public.ticket_media where ticket_id = p_ticket_id;
  if (p_kind = 'foto' and (v_photos >= 3 or v_videos > 0)) or (p_kind = 'video' and (v_videos >= 1 or v_photos > 0)) then
    raise exception 'En fazla 3 fotoğraf ya da 1 video eklenebilir' using errcode = 'SD011';
  end if;
  if not exists (select 1 from storage.objects where bucket_id = 'kayitlar' and name = p_path) then
    raise exception 'Dosya yüklenmemiş' using errcode = '22023';
  end if;
  insert into public.ticket_media (ticket_id, site_id, kind, path, size_bytes, duration_ms) values (p_ticket_id, v_t.site_id, p_kind, p_path, p_size, p_duration_ms);
end;
$$;

-- Not yaz (sakin, danışma, yönetici)
create function public.add_ticket_note(p_ticket_id uuid, p_body text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_role text := public.ticket_role(p_ticket_id);
  v_site uuid;
begin
  if v_role is null then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if length(trim(coalesce(p_body, ''))) < 1 then raise exception 'Not boş olamaz' using errcode = '22023'; end if;
  select site_id into v_site from public.tickets where id = p_ticket_id;
  insert into public.ticket_events (ticket_id, site_id, kind, body, author_id, author_name, author_role)
  values (p_ticket_id, v_site, 'not', left(trim(p_body), 1000), auth.uid(), public.my_name(), v_role);
  update public.tickets set updated_at = now() where id = p_ticket_id;
end;
$$;

-- Durumu değiştir (sadece yönetici); isteğe bağlı cevapla
create function public.set_ticket_status(p_ticket_id uuid, p_status text, p_body text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_site uuid;
begin
  if public.ticket_role(p_ticket_id) is distinct from 'yonetici' then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if p_status not in ('alindi', 'inceleniyor', 'yapiliyor', 'tamamlandi') then raise exception 'Durum hatalı' using errcode = '22023'; end if;
  update public.tickets set status = p_status, updated_at = now(),
    closed_at = case when p_status = 'tamamlandi' then now() end,
    resolution = case when p_status = 'tamamlandi' then null else resolution end
  where id = p_ticket_id returning site_id into v_site;
  insert into public.ticket_events (ticket_id, site_id, kind, status, body, author_id, author_name, author_role)
  values (p_ticket_id, v_site, 'durum', p_status, nullif(left(trim(coalesce(p_body, '')), 1000), ''), auth.uid(), public.my_name(), 'yonetici');
end;
$$;

-- Sakin tamamlanan kaydı onaylar ya da "sorun devam ediyor" der (devam → inceleniyor'a döner)
create function public.resolve_ticket(p_ticket_id uuid, p_solved boolean, p_body text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_t public.tickets;
begin
  select * into v_t from public.tickets where id = p_ticket_id;
  if public.ticket_role(p_ticket_id) is distinct from 'sakin' then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if v_t.status <> 'tamamlandi' then raise exception 'Kayıt henüz tamamlanmadı' using errcode = '22023'; end if;
  update public.tickets set resolution = case when p_solved then 'cozuldu' else 'devam' end,
    status = case when p_solved then 'tamamlandi' else 'inceleniyor' end,
    closed_at = case when p_solved then closed_at end, updated_at = now()
  where id = p_ticket_id;
  insert into public.ticket_events (ticket_id, site_id, kind, status, body, author_id, author_name, author_role)
  values (p_ticket_id, v_t.site_id, 'sonuc', case when p_solved then 'cozuldu' else 'devam' end,
          nullif(left(trim(coalesce(p_body, '')), 1000), ''), auth.uid(), public.my_name(), 'sakin');
end;
$$;

create trigger audit after insert or update or delete on public.tickets for each row execute function public.write_audit();

-- ---------- Yetkiler ----------
alter table public.tickets enable row level security;
alter table public.ticket_events enable row level security;
alter table public.ticket_media enable row level security;
revoke all on public.tickets, public.ticket_events, public.ticket_media from anon, authenticated;
grant select on public.tickets, public.ticket_events, public.ticket_media to authenticated;

create policy "kayıt görme" on public.tickets for select to authenticated
  using (site_id in (select public.my_site_ids('{yonetici,danisma}'))
         or unit_id in (select ur.unit_id from public.unit_residents ur join public.residents r on r.id = ur.resident_id
                        where ur.ended_on is null and r.user_id = (select auth.uid())));
create policy "kayıt olayı görme" on public.ticket_events for select to authenticated
  using (ticket_id in (select id from public.tickets));
create policy "kayıt dosyası görme" on public.ticket_media for select to authenticated
  using (ticket_id in (select id from public.tickets));

revoke execute on function public.ticket_role(uuid), public.my_name(), public.create_ticket(uuid, uuid, text, text, text, text, boolean),
  public.add_ticket_media(uuid, text, text, integer, integer), public.add_ticket_note(uuid, text), public.set_ticket_status(uuid, text, text),
  public.resolve_ticket(uuid, boolean, text) from public, anon;
grant execute on function public.ticket_role(uuid), public.create_ticket(uuid, uuid, text, text, text, text, boolean),
  public.add_ticket_media(uuid, text, text, integer, integer), public.add_ticket_note(uuid, text), public.set_ticket_status(uuid, text, text),
  public.resolve_ticket(uuid, boolean, text) to authenticated;

-- ---------- Dosya deposu (herkese kapalı) ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('kayitlar', 'kayitlar', false, 52428800, array['image/jpeg', 'video/mp4', 'video/quicktime'])
on conflict (id) do nothing;

-- Yol: {site_id}/{ticket_id}/{dosya}. Okuma: kayda erişimi olan; yükleme: kayda erişimi olan ve kayıt tamamlanmamışsa.
create function public.storage_ticket_id(p_name text)
returns uuid language sql immutable set search_path = ''
as $$ select case when split_part(p_name, '/', 2) ~ '^[0-9a-f-]{36}$' then split_part(p_name, '/', 2)::uuid end $$;

create policy "kayıt dosyası okuma" on storage.objects for select to authenticated
  using (bucket_id = 'kayitlar' and public.ticket_role(public.storage_ticket_id(name)) is not null);
create policy "kayıt dosyası yükleme" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'kayitlar'
    and public.ticket_role(public.storage_ticket_id(name)) is not null
    and exists (select 1 from public.tickets t where t.id = public.storage_ticket_id(name)
                and split_part(name, '/', 1) = t.site_id::text and t.status <> 'tamamlandi')
  );
