-- Genel kurul toplantı tutanağı (kullanıcı kararı, 05.10.2026)
-- • Yönetici toplantıyı kaydeder: tarih, yer, olağan/olağanüstü, divan (başkan, yazman), katılan villa/daireler
--   (kendisi veya vekili), gündem maddeleri ve her maddenin kararı (kabul / ret / çekimser oy sayısı).
-- • Taslak serbestçe düzenlenir ve silinebilir; "Kesinleştir" sonrası değiştirilemez ve silinemez (yazdırılıp imzalanır).
-- • Danışma göremez. Mevcut kayıtlar değişmez.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

create table public.meetings (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  meeting_date date not null,
  meeting_time text check (meeting_time is null or meeting_time ~ '^\d{2}:\d{2}$'),
  place text check (place is null or length(place) <= 200),
  kind text not null default 'olagan' check (kind in ('olagan', 'olaganustu')),
  chair text check (chair is null or length(chair) <= 100),
  secretary text check (secretary is null or length(secretary) <= 100),
  -- [{unit_id, name, proxy}] : katılan birim, imza atacak kişi, vekil mi
  attendees jsonb not null default '[]'::jsonb check (jsonb_typeof(attendees) = 'array' and jsonb_array_length(attendees) <= 2000),
  -- [{title, discussion, decision, yes, no, abstain}]
  agenda jsonb not null default '[]'::jsonb check (jsonb_typeof(agenda) = 'array' and jsonb_array_length(agenda) <= 50),
  notes text check (notes is null or length(notes) <= 4000),
  status text not null default 'taslak' check (status in ('taslak', 'kesin')),
  finalized_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  updated_at timestamptz not null default now()
);
create index on public.meetings (site_id, meeting_date desc);

alter table public.meetings enable row level security;
revoke all on public.meetings from public, anon, authenticated;
grant select, insert, delete on public.meetings to authenticated;
grant update (meeting_date, meeting_time, place, kind, chair, secretary, attendees, agenda, notes, status, updated_at) on public.meetings to authenticated;

create policy "toplantı görme" on public.meetings for select to authenticated
  using ((select public.has_site_role(site_id, '{yonetici}')) or (select public.is_site_viewer(site_id)));
create policy "toplantı ekleme" on public.meetings for insert to authenticated
  with check ((select public.has_site_role(site_id, '{yonetici}')) and status = 'taslak');
create policy "toplantı düzenleme" on public.meetings for update to authenticated
  using ((select public.has_site_role(site_id, '{yonetici}')) and status = 'taslak')
  with check ((select public.has_site_role(site_id, '{yonetici}')));
create policy "taslak silme" on public.meetings for delete to authenticated
  using ((select public.has_site_role(site_id, '{yonetici}')) and status = 'taslak');

-- Kesinleşen tutanak değişmez; katılanlar sadece o sitenin birimleri olabilir
create function public.meeting_guard()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and old.status = 'kesin' then
    raise exception 'Kesinleşmiş tutanak değiştirilemez' using errcode = '42501';
  end if;
  if exists (
    select 1 from jsonb_array_elements(new.attendees) a
    where not exists (select 1 from public.units u where u.id = (a->>'unit_id')::uuid and u.site_id = new.site_id)
  ) then
    raise exception 'Katılan listesinde bu siteye ait olmayan birim var' using errcode = '22023';
  end if;
  if new.status = 'kesin' then
    if new.chair is null or length(trim(new.chair)) < 3 or jsonb_array_length(new.agenda) = 0 then
      raise exception 'Kesinleştirmek için divan başkanı ve en az bir gündem maddesi gerekli' using errcode = '22023';
    end if;
    new.finalized_at := now();
  end if;
  new.updated_at := now();
  return new;
end;
$$;
revoke execute on function public.meeting_guard() from public, anon, authenticated;
create trigger meeting_guard before insert or update on public.meetings for each row execute function public.meeting_guard();
