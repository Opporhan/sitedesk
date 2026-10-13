-- Demo sitesi işareti: sahte verilerle tanıtım sitesi. Bildirim gönderilmez, ekranda "Örnek veri" yazar.
-- scripts/demo.sql sadece is_demo = true olan siteyi silip yeniden kurar.
set local lock_timeout = '15s';
set local statement_timeout = '60s';
alter table public.sites add column is_demo boolean not null default false;
