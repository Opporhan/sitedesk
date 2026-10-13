-- Yetki denetimi (02.10.2026): danışma görevlisi "hukuki takip" bilgisini (borçlu olduğunu gösterir) doğrudan sorguyla görebiliyordu.
-- Bu iki kolon artık birim tablosundan okunamaz; sadece yönetici yetkisi (ve salt okunur izleyici) ayrı görünümden okur.
-- Kayıtlar değişmez.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

revoke select on public.units from authenticated;
grant select (id, site_id, block_id, no, type, created_at, created_by) on public.units to authenticated;

-- Görünüm sahibinin yetkisiyle çalışır; kimin görebileceğini içindeki koşul belirler
create view public.unit_legal with (security_invoker = false) as
  select u.id as unit_id, u.site_id, u.legal_since, u.legal_note
  from public.units u
  where public.has_site_role(u.site_id, '{yonetici}') or public.is_site_viewer(u.site_id);

revoke all on public.unit_legal from public, anon, authenticated;
grant select on public.unit_legal to authenticated;
