-- Faz 3.3: Arızalar — danışma (ve yönetici) kaydeder, durumu günceller, kapatır (kullanıcı kararı)
-- Villaya bağlı veya ortak alan (unit_id boş). Kategori yok (sade); "Acil" işareti var.
-- Durum: acik → yapiliyor → tamamlandi; her değişiklik ve not geçmişe yazılır (ticket_updates).
-- Fotoğraf: en fazla 3, gizli "ariza" kovası, yol {site_id}/ariza/{ariza_id}/{dosya}.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

create type public.ticket_status as enum ('acik', 'yapiliyor', 'tamamlandi');

create table public.tickets (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  unit_id uuid,
  description text not null check (length(trim(description)) between 3 and 1000),
  urgent boolean not null default false,
  status public.ticket_status not null default 'acik',
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  foreign key (unit_id, site_id) references public.units (id, site_id) on delete restrict,
  unique (id, site_id)
);

create index on public.tickets (site_id, status, created_at desc);

create table public.ticket_updates (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null,
  site_id uuid not null,
  status public.ticket_status,
  note text check (note is null or length(note) <= 1000),
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  foreign key (ticket_id, site_id) references public.tickets (id, site_id) on delete cascade,
  check (status is not null or note is not null)
);

create index on public.ticket_updates (ticket_id, created_at);

create table public.ticket_photos (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null,
  site_id uuid not null,
  path text not null unique,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  foreign key (ticket_id, site_id) references public.tickets (id, site_id) on delete cascade,
  check (path like site_id::text || '/ariza/' || ticket_id::text || '/%')
);

-- Arıza başına en fazla 3 fotoğraf
create function public.limit_ticket_photos()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtext(new.ticket_id::text));
  if (select count(*) from public.ticket_photos where ticket_id = new.ticket_id) >= 3 then
    raise exception 'Bir arızaya en fazla 3 fotoğraf eklenebilir' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger ticket_photos_limit before insert on public.ticket_photos
  for each row execute function public.limit_ticket_photos();

revoke all on public.tickets, public.ticket_updates, public.ticket_photos from anon, authenticated;
grant select on public.tickets, public.ticket_updates, public.ticket_photos to authenticated;
grant insert (site_id, unit_id, description, urgent) on public.tickets to authenticated;
grant insert (ticket_id, site_id, path) on public.ticket_photos to authenticated;
alter table public.tickets enable row level security;
alter table public.ticket_updates enable row level security;
alter table public.ticket_photos enable row level security;

create policy "arıza görme" on public.tickets
  for select to authenticated using (public.has_site_role(site_id, '{yonetici,danisma}'));
create policy "arıza kaydı" on public.tickets
  for insert to authenticated with check (public.has_site_role(site_id, '{yonetici,danisma}'));
create policy "arıza geçmişi görme" on public.ticket_updates
  for select to authenticated using (public.has_site_role(site_id, '{yonetici,danisma}'));
create policy "arıza fotoğrafı görme" on public.ticket_photos
  for select to authenticated using (public.has_site_role(site_id, '{yonetici,danisma}'));
create policy "arıza fotoğrafı ekleme" on public.ticket_photos
  for insert to authenticated with check (public.has_site_role(site_id, '{yonetici,danisma}'));

-- Durum değiştir ve/veya not ekle (geçmişe yazılır)
create function public.update_ticket(p_ticket_id uuid, p_status public.ticket_status, p_note text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_ticket public.tickets;
  v_note text := nullif(trim(left(p_note, 1000)), '');
begin
  select * into v_ticket from public.tickets where id = p_ticket_id;
  if v_ticket.id is null or not public.has_site_role(v_ticket.site_id, '{yonetici,danisma}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if p_status is not null and p_status = v_ticket.status then
    p_status := null; -- aynı durum: sadece not
  end if;
  if p_status is null and v_note is null then
    raise exception 'Durum veya not girilmeli' using errcode = '22023';
  end if;

  if p_status is not null then
    update public.tickets
    set status = p_status, closed_at = case when p_status = 'tamamlandi' then now() end
    where id = p_ticket_id;
  end if;
  insert into public.ticket_updates (ticket_id, site_id, status, note)
  values (p_ticket_id, v_ticket.site_id, p_status, v_note);
end;
$$;

revoke execute on function public.update_ticket(uuid, public.ticket_status, text) from public, anon;
grant execute on function public.update_ticket(uuid, public.ticket_status, text) to authenticated;

-- Fotoğraf kovası (gizli; sadece JPEG/PNG/WebP; 4 MB)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ariza', 'ariza', false, 4194304, array['image/jpeg', 'image/png', 'image/webp']);

create policy "arıza fotoğrafı dosya görme" on storage.objects
  for select to authenticated
  using (bucket_id = 'ariza' and public.path_site_id(name) is not null
         and public.has_site_role(public.path_site_id(name), '{yonetici,danisma}'));
create policy "arıza fotoğrafı dosya yükleme" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'ariza' and public.path_site_id(name) is not null
              and public.has_site_role(public.path_site_id(name), '{yonetici,danisma}'));
