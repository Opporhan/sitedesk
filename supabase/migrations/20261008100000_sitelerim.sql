-- Sitelerim (kullanıcı onayı 08.10.2026): birden çok siteyi yöneten kişi bütün sitelerini tek ekranda görür.
-- Sadece okur; hiçbir tabloyu değiştirmez. Yönetici: yönettiği AKTİF siteler; sistem yöneticisi: bütün siteler (kapalılar dahil).
-- Danışma ve sakin için boş liste döner.
create function public.my_sites_overview()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(x order by x ->> 'name'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'site_id', s.id,
      'name', s.name,
      'type', s.type,
      'active', s.active,
      'open_tickets', (select count(*) from public.tickets t where t.site_id = s.id and t.status <> 'tamamlandi'),
      'urgent_open', (select count(*) from public.tickets t where t.site_id = s.id and t.status <> 'tamamlandi' and t.urgent),
      'new_tickets', (select count(*) from public.tickets t where t.site_id = s.id and t.status = 'alindi'),
      'waiting_packages', (select count(*) from public.packages p where p.site_id = s.id and p.delivered_at is null),
      'inside_visitors', (select count(*) from public.visitors v where v.site_id = s.id and v.departed_at is null and v.arrived_at > now() - interval '7 days')
    ) as x
    from public.sites s
    where s.id in (select public.my_site_ids('{yonetici}'))
  ) q
$$;
revoke execute on function public.my_sites_overview() from public, anon;
grant execute on function public.my_sites_overview() to authenticated;
