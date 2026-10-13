-- Faz 2: Hatırlatma kaydı — WhatsApp borç hatırlatması açıldığında kim, ne zaman, ne kadar için yazıldı
-- (WhatsApp'ta Gönder'e basıldığını uygulama bilemez; kayıt "hazır mesaj açıldı" anlamındadır.)
-- Kayıtlar değişmez ve silinmez.

create table public.reminders (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null,
  unit_id uuid not null,
  resident_id uuid references public.residents (id) on delete set null,
  amount numeric(12, 2) not null check (amount > 0),
  sent_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  foreign key (unit_id, site_id) references public.units (id, site_id) on delete restrict
);

create index on public.reminders (site_id, unit_id, sent_at desc);

revoke all on public.reminders from anon, authenticated;
grant select on public.reminders to authenticated;
grant insert (site_id, unit_id, resident_id, amount) on public.reminders to authenticated;
alter table public.reminders enable row level security;

create policy "hatırlatma görme" on public.reminders
  for select to authenticated using (public.has_site_role(site_id, '{yonetici}'));
create policy "hatırlatma kaydı" on public.reminders
  for insert to authenticated with check (
    public.has_site_role(site_id, '{yonetici}')
    and (resident_id is null or exists (select 1 from public.residents r where r.id = resident_id and r.site_id = reminders.site_id))
  );
