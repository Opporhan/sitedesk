-- Uygulama bildirimleri (Web Push) — kullanıcı kararı: Telegram ve e-posta yok
-- push_subscriptions: hangi cihaz bildirim alır (kişi sadece kendi cihazlarını görür/ekler/siler).
-- notification_log: gönderilen bildirimler; aynı bildirim (ör. bir ayın özeti) iki kez gitmez.
-- Gönderim sunucuda gizli anahtarla yapılır (Vercel); Mac'ten bağımsız.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

create table public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  endpoint text not null unique check (endpoint like 'https://%'),
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz not null default now()
);

create index on public.push_subscriptions (user_id);

revoke all on public.push_subscriptions from anon, authenticated;
grant select, delete on public.push_subscriptions to authenticated;
grant insert (endpoint, p256dh, auth, user_agent) on public.push_subscriptions to authenticated;
alter table public.push_subscriptions enable row level security;

create policy "kendi cihazlarım" on public.push_subscriptions
  for select to authenticated using (user_id = (select auth.uid()));
create policy "cihaz ekleme" on public.push_subscriptions
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "cihaz silme" on public.push_subscriptions
  for delete to authenticated using (user_id = (select auth.uid()));

create table public.notification_log (
  id uuid primary key default gen_random_uuid(),
  site_id uuid references public.sites (id) on delete cascade,
  kind text not null,
  ref_key text not null,
  sent_count integer not null default 0,
  sent_at timestamptz not null default now(),
  unique (site_id, kind, ref_key)
);

-- Sadece sunucu (gizli anahtar) yazar ve okur
revoke all on public.notification_log from anon, authenticated;
alter table public.notification_log enable row level security;
