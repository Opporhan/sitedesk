-- Duyurular: WhatsApp grubuna yapıştırılacak hazır metinlerin arşivi
-- Yönetici yazar (şablondan veya serbest); aidat tutarı bütçeden uygulanınca sistem de ekler (auto).
-- Danışma göremez. Arşiv silinmez.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  title text not null check (length(trim(title)) between 2 and 120),
  body text not null check (length(trim(body)) between 5 and 4000),
  auto boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null
);

create index on public.announcements (site_id, created_at desc);

revoke all on public.announcements from anon, authenticated;
grant select on public.announcements to authenticated;
grant insert (site_id, title, body, auto) on public.announcements to authenticated;
alter table public.announcements enable row level security;

create policy "duyuru görme" on public.announcements
  for select to authenticated using (public.has_site_role(site_id, '{yonetici}'));
create policy "duyuru yazma" on public.announcements
  for insert to authenticated with check (public.has_site_role(site_id, '{yonetici}'));
