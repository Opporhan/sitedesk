-- Bütçede belirlenen daire/villa başı aylık aidat (işletme projesinde yazan tutar; sistem hesaplamaz, girilir)
alter table public.budgets add column unit_due numeric(12, 2) check (unit_due is null or unit_due > 0);
grant update (unit_due) on public.budgets to authenticated;

create policy "bütçe düzenleme" on public.budgets
  for update to authenticated
  using (public.has_site_role(site_id, '{yonetici}'))
  with check (public.has_site_role(site_id, '{yonetici}'));
