-- Adım 6: kargo ve ziyaretçi (eski sürümün mantığıyla; kullanıcı kararları 07.10.2026)
-- • Kayıtları danışma ve yönetici girer. Kargo: kaydet → teslim et (kime, isteğe bağlı); yanlış teslim AYNI GÜN geri alınır,
--   yanlış daireye girilen ve teslim edilmemiş kargo AYNI GÜN silinir.
-- • Ziyaretçi: daire + ad + isteğe bağlı plaka; giriş saati kendiliğinden. "Çıkış yaptı" (saat kendiliğinden), aynı gün geri alınır;
--   aynı gün girilen yanlış kayıt silinir. 1 yıldan eski ziyaretçi kayıtları her gece silinir (kişisel veri).
-- • Sakin kendi dairesinin kargolarını ve ZİYARETÇİLERİNİ görür (ziyaretçi: son 30 gün). Kiracı sadece kendi taşınmasından
--   sonrasını görür; dairede oturan kiracı varken malik ziyaretçileri görmez (kiracının hanesi).
-- • Zayıf internet: her kaydın uygulamadan gelen kimliği (client_id) var; tekrar gönderilirse ikinci kayıt açılmaz.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

create table public.packages (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null,
  unit_id uuid not null,
  client_id uuid not null unique,
  note text check (note is null or length(note) <= 200),
  received_at timestamptz not null default now(),
  received_by uuid default auth.uid() references auth.users (id) on delete set null,
  delivered_at timestamptz,
  delivered_to text check (delivered_to is null or length(delivered_to) <= 100),
  delivered_by uuid references auth.users (id) on delete set null,
  foreign key (unit_id, site_id) references public.units (id, site_id) on delete restrict
);
create index on public.packages (site_id, delivered_at, received_at desc);
create index on public.packages (unit_id, received_at desc);

create table public.visitors (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null,
  unit_id uuid not null,
  client_id uuid not null unique,
  visitor_name text not null check (length(trim(visitor_name)) between 2 and 100),
  plate text check (plate is null or plate ~ '^[0-9A-ZÇĞİÖŞÜ]{2,12}$'),
  arrived_at timestamptz not null default now(),
  arrived_by uuid default auth.uid() references auth.users (id) on delete set null,
  departed_at timestamptz,
  departed_by uuid references auth.users (id) on delete set null,
  foreign key (unit_id, site_id) references public.units (id, site_id) on delete restrict
);
create index on public.visitors (site_id, departed_at, arrived_at desc);
create index on public.visitors (unit_id, arrived_at desc);

create trigger audit after insert or update or delete on public.packages for each row execute function public.write_audit();
create trigger audit after insert or update or delete on public.visitors for each row execute function public.write_audit();

-- Türkiye saatiyle bugün mü?
create function public.is_today_tr(p_at timestamptz)
returns boolean language sql stable set search_path = ''
as $$ select (p_at at time zone 'Europe/Istanbul')::date = (now() at time zone 'Europe/Istanbul')::date $$;

-- ---------- Kargo ----------
create function public.record_package(p_client_id uuid, p_unit_id uuid, p_note text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_site uuid; v_id uuid;
begin
  select id into v_id from public.packages where client_id = p_client_id;
  if v_id is not null then return v_id; end if;
  select site_id into v_site from public.units where id = p_unit_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici,danisma}') then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  insert into public.packages (site_id, unit_id, client_id, note) values (v_site, p_unit_id, p_client_id, nullif(left(trim(coalesce(p_note, '')), 200), ''))
  returning id into v_id;
  return v_id;
end;
$$;

create function public.deliver_package(p_package_id uuid, p_to text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_p public.packages;
begin
  select * into v_p from public.packages where id = p_package_id for update;
  if v_p.id is null or not public.has_site_role(v_p.site_id, '{yonetici,danisma}') then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if v_p.delivered_at is not null then return; end if; -- iki kez teslim olmaz
  update public.packages set delivered_at = now(), delivered_by = auth.uid(), delivered_to = nullif(left(trim(coalesce(p_to, '')), 100), '') where id = p_package_id;
end;
$$;

create function public.undo_package_delivery(p_package_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_p public.packages;
begin
  select * into v_p from public.packages where id = p_package_id for update;
  if v_p.id is null or not public.has_site_role(v_p.site_id, '{yonetici,danisma}') then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if v_p.delivered_at is null or not public.is_today_tr(v_p.delivered_at) then raise exception 'Sadece bugün yapılan teslim geri alınabilir' using errcode = '22023'; end if;
  update public.packages set delivered_at = null, delivered_by = null, delivered_to = null where id = p_package_id;
end;
$$;

create function public.delete_package(p_package_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_p public.packages;
begin
  select * into v_p from public.packages where id = p_package_id for update;
  if v_p.id is null or not public.has_site_role(v_p.site_id, '{yonetici,danisma}') then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if v_p.delivered_at is not null or not public.is_today_tr(v_p.received_at) then raise exception 'Sadece bugün girilen, teslim edilmemiş kargo silinebilir' using errcode = '22023'; end if;
  delete from public.packages where id = p_package_id;
end;
$$;

-- ---------- Ziyaretçi ----------
create function public.record_visitor(p_client_id uuid, p_unit_id uuid, p_name text, p_plate text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_site uuid; v_id uuid; v_plate text;
begin
  select id into v_id from public.visitors where client_id = p_client_id;
  if v_id is not null then return v_id; end if;
  select site_id into v_site from public.units where id = p_unit_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici,danisma}') then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  -- Plaka büyük harf, boşluk/tire atılır ("34 abc 123" → "34ABC123")
  v_plate := nullif(regexp_replace(upper(coalesce(p_plate, '')), '[^0-9A-ZÇĞİÖŞÜ]', '', 'g'), '');
  insert into public.visitors (site_id, unit_id, client_id, visitor_name, plate) values (v_site, p_unit_id, p_client_id, trim(p_name), v_plate)
  returning id into v_id;
  return v_id;
end;
$$;

create function public.mark_visitor_departed(p_visitor_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_v public.visitors;
begin
  select * into v_v from public.visitors where id = p_visitor_id for update;
  if v_v.id is null or not public.has_site_role(v_v.site_id, '{yonetici,danisma}') then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if v_v.departed_at is not null then return; end if;
  update public.visitors set departed_at = now(), departed_by = auth.uid() where id = p_visitor_id;
end;
$$;

create function public.undo_visitor_departure(p_visitor_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_v public.visitors;
begin
  select * into v_v from public.visitors where id = p_visitor_id for update;
  if v_v.id is null or not public.has_site_role(v_v.site_id, '{yonetici,danisma}') then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if v_v.departed_at is null or not public.is_today_tr(v_v.departed_at) then raise exception 'Sadece bugünkü çıkış geri alınabilir' using errcode = '22023'; end if;
  update public.visitors set departed_at = null, departed_by = null where id = p_visitor_id;
end;
$$;

create function public.delete_visitor(p_visitor_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_v public.visitors;
begin
  select * into v_v from public.visitors where id = p_visitor_id for update;
  if v_v.id is null or not public.has_site_role(v_v.site_id, '{yonetici,danisma}') then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if not public.is_today_tr(v_v.arrived_at) then raise exception 'Sadece bugün girilen kayıt silinebilir' using errcode = '22023'; end if;
  delete from public.visitors where id = p_visitor_id;
end;
$$;

-- Sakin bu kaydı görebilir mi? (kargo: taşınmasından sonra gelenler; ziyaretçi: ayrıca son 30 gün ve kiracı varken malik göremez)
create function public.resident_can_see(p_unit_id uuid, p_at timestamptz, p_visitor boolean)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.unit_residents ur
    join public.residents r on r.id = ur.resident_id
    join public.sites s on s.id = ur.site_id
    where ur.unit_id = p_unit_id and ur.ended_on is null and s.active and r.user_id = (select auth.uid())
      and p_at >= (ur.started_on::timestamp at time zone 'Europe/Istanbul')
      and (not p_visitor or (
            p_at >= now() - interval '30 days'
            and (ur.relation = 'kiraci' or not exists (
                   select 1 from public.unit_residents k where k.unit_id = p_unit_id and k.ended_on is null and k.relation = 'kiraci'))))
  )
$$;

-- 1 yıldan eski ziyaretçi kayıtları (her gece 01:30)
create function public.purge_old_visitors()
returns integer language sql security definer set search_path = ''
as $$
  with d as (delete from public.visitors where arrived_at < now() - interval '1 year' returning 1) select count(*)::int from d
$$;
revoke execute on function public.purge_old_visitors() from public, anon, authenticated;
select cron.schedule('ziyaretci-temizlik', '30 1 * * *', $$select public.purge_old_visitors()$$);

-- ---------- Yetkiler ----------
alter table public.packages enable row level security;
alter table public.visitors enable row level security;
revoke all on public.packages, public.visitors from anon, authenticated;
grant select on public.packages, public.visitors to authenticated;
create policy "kargo görme" on public.packages for select to authenticated
  using (site_id in (select public.my_site_ids('{yonetici,danisma}')) or public.resident_can_see(unit_id, received_at, false));
create policy "ziyaretçi görme" on public.visitors for select to authenticated
  using (site_id in (select public.my_site_ids('{yonetici,danisma}')) or public.resident_can_see(unit_id, arrived_at, true));

revoke execute on function public.record_package(uuid, uuid, text), public.deliver_package(uuid, text), public.undo_package_delivery(uuid),
  public.delete_package(uuid), public.record_visitor(uuid, uuid, text, text), public.mark_visitor_departed(uuid),
  public.undo_visitor_departure(uuid), public.delete_visitor(uuid), public.resident_can_see(uuid, timestamptz, boolean), public.is_today_tr(timestamptz) from public, anon;
grant execute on function public.record_package(uuid, uuid, text), public.deliver_package(uuid, text), public.undo_package_delivery(uuid),
  public.delete_package(uuid), public.record_visitor(uuid, uuid, text, text), public.mark_visitor_departed(uuid),
  public.undo_visitor_departure(uuid), public.delete_visitor(uuid) to authenticated;
