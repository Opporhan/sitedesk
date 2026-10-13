-- İzleyici (salt okunur demo hesabı): sadece üyesi olduğu sitenin verisini OKUR.
-- Yazma/değiştirme/iptal kurallarına ve güvenlik fonksiyonlarına (has_site_role) dokunulmaz → izleyici yazamaz.
-- Her tabloya ayrı bir SELECT kuralı eklenir (mevcut kurallar değişmez).

set local lock_timeout = '15s';
set local statement_timeout = '60s';

create function public.is_site_viewer(p_site_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.memberships
    where user_id = (select auth.uid()) and site_id = p_site_id and role = 'izleyici' and ended_on is null
  );
$$;

revoke execute on function public.is_site_viewer(uuid) from public, anon;
grant execute on function public.is_site_viewer(uuid) to authenticated;

do $$
declare
  t text;
begin
  foreach t in array array[
    'announcements', 'audit_log', 'bank_checks', 'blocks', 'budget_items', 'budgets', 'cash_documents', 'cash_entries',
    'dues', 'maintenance_logs', 'maintenance_tasks', 'packages', 'payments', 'reminders', 'residents', 'site_managers',
    'ticket_photos', 'ticket_updates', 'tickets', 'unit_due_rates', 'unit_residents', 'units', 'visitors'
  ] loop
    execute format(
      'create policy "izleyici görme" on public.%I for select to authenticated using (public.is_site_viewer(site_id))', t);
  end loop;
end;
$$;

-- Belge ve arıza fotoğrafları (dosyalar): izleyici sadece görür
create policy "izleyici belge görme" on storage.objects
  for select to authenticated
  using (bucket_id in ('belgeler', 'ariza') and public.path_site_id(name) is not null
         and public.is_site_viewer(public.path_site_id(name)));
