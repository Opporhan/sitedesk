-- Gün 3: Banka dosyasından gider ve diğer gelir aktarımı + eşleştirme hafızası

-- Kasa kayıtları da banka hareketinden gelebilir; aynı hareket iki kez kaydedilemez
alter table public.cash_entries add column bank_ref text;
create unique index cash_entries_bank_ref_unique on public.cash_entries (site_id, bank_ref) where bank_ref is not null and status = 'aktif';
grant insert (bank_ref) on public.cash_entries to authenticated;

-- Hafıza: "bu gönderen/açıklama hep şuraya gider"
create table public.bank_rules (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  match_key text not null check (length(match_key) >= 3),
  target text not null check (target in ('aidat', 'gelir', 'gider', 'alma')),
  unit_id uuid,
  category text, -- gelir kategorisi veya gider bütçe kaleminin adı (yıllar arası kalem adı sabit kalır)
  updated_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  foreign key (unit_id, site_id) references public.units (id, site_id) on delete cascade,
  unique (site_id, match_key),
  check ((target = 'aidat') = (unit_id is not null)),
  check ((target in ('gelir', 'gider')) = (category is not null))
);

revoke all on public.bank_rules from anon, authenticated;
grant select, insert, delete on public.bank_rules to authenticated;
grant update (target, unit_id, category, updated_at) on public.bank_rules to authenticated;
alter table public.bank_rules enable row level security;

create policy "banka hafızası" on public.bank_rules
  for all to authenticated
  using (public.has_site_role(site_id, '{yonetici}'))
  with check (public.has_site_role(site_id, '{yonetici}'));
