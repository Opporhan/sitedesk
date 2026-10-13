-- Faz 3.1: Kargo — danışma kaydeder, sakine WhatsApp ile haber verir, teslim edince işaretler
-- Haber verme ve teslim sadece fonksiyonlarla (kim, ne zaman otomatik yazılır).

create table public.packages (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null,
  unit_id uuid not null,
  carrier text not null check (length(trim(carrier)) between 1 and 60),
  note text check (note is null or length(note) <= 200),
  received_at timestamptz not null default now(),
  notified_at timestamptz,
  delivered_at timestamptz,
  delivered_to text check (delivered_to is null or length(delivered_to) <= 100),
  delivered_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  foreign key (unit_id, site_id) references public.units (id, site_id) on delete restrict
);

create index on public.packages (site_id, received_at desc);
create index on public.packages (site_id) where delivered_at is null;

revoke all on public.packages from anon, authenticated;
grant select on public.packages to authenticated;
grant insert (site_id, unit_id, carrier, note) on public.packages to authenticated;
alter table public.packages enable row level security;

create policy "kargo görme" on public.packages
  for select to authenticated using (public.has_site_role(site_id, '{yonetici,danisma}'));
create policy "kargo kaydı" on public.packages
  for insert to authenticated with check (public.has_site_role(site_id, '{yonetici,danisma}'));

-- Sakine WhatsApp ile haber verildi (hazır mesaj açıldı)
create function public.mark_package_notified(p_package_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
begin
  select site_id into v_site from public.packages where id = p_package_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici,danisma}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  update public.packages set notified_at = now() where id = p_package_id and delivered_at is null;
end;
$$;

-- Teslim edildi (kime teslim edildiği isteğe bağlı)
create function public.deliver_package(p_package_id uuid, p_delivered_to text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
begin
  select site_id into v_site from public.packages where id = p_package_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici,danisma}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  update public.packages
  set delivered_at = now(), delivered_by = auth.uid(), delivered_to = nullif(trim(left(p_delivered_to, 100)), '')
  where id = p_package_id and delivered_at is null;
  if not found then
    raise exception 'Bu kargo zaten teslim edilmiş' using errcode = '22023';
  end if;
end;
$$;

-- Yanlışlıkla "teslim edildi" denirse aynı gün geri alınabilir
create function public.undo_package_delivery(p_package_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
begin
  select site_id into v_site from public.packages where id = p_package_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici,danisma}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  update public.packages set delivered_at = null, delivered_by = null, delivered_to = null
  where id = p_package_id
    and (delivered_at at time zone 'Europe/Istanbul')::date = (now() at time zone 'Europe/Istanbul')::date;
  if not found then
    raise exception 'Sadece bugün yapılan teslim geri alınabilir' using errcode = '22023';
  end if;
end;
$$;

revoke execute on function public.mark_package_notified(uuid) from public, anon;
revoke execute on function public.deliver_package(uuid, text) from public, anon;
revoke execute on function public.undo_package_delivery(uuid) from public, anon;
grant execute on function public.mark_package_notified(uuid) to authenticated;
grant execute on function public.deliver_package(uuid, text) to authenticated;
grant execute on function public.undo_package_delivery(uuid) to authenticated;
