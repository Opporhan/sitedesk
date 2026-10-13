-- Hızlandırma (06.10.2026, 600 dairelik deneme sonrası): güvenlik kuralları yetkiyi her satır için ayrı soruyordu
-- (has_site_role / is_site_viewer satır başına çalışıyordu; 6.000 borçta ≈ 1 sn).
-- Artık kural, kişinin yetkili olduğu siteleri BİR KEZ bulur ve satırın sitesini bu listede arar.
-- Kimin neyi görebildiği DEĞİŞMEZ (aynı rol ve aynı "ayrılmamış üyelik" şartı); sadece hesap yöntemi değişir.
-- Kurallar otomatik dönüştürülür: "has_site_role(site_id, roller)" → "site_id in (select my_site_ids(roller))",
-- "is_site_viewer(site_id)" → "site_id in (select my_viewer_site_ids())". Diğer kurallara dokunulmaz.

set local lock_timeout = '15s';
set local statement_timeout = '120s';

-- Kişinin belirtilen rollerle yetkili olduğu siteler (sistem yöneticisi: bütün siteler) — has_site_role ile aynı kural
create function public.my_site_ids(p_roles public.site_role[])
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select s.id from public.sites s where public.is_platform_admin()
  union
  select m.site_id from public.memberships m
  where m.user_id = (select auth.uid()) and m.role = any (p_roles) and m.ended_on is null
$$;
revoke execute on function public.my_site_ids(public.site_role[]) from public, anon;
grant execute on function public.my_site_ids(public.site_role[]) to authenticated;

-- Salt okunur izleyicinin siteleri — is_site_viewer ile aynı kural
create function public.my_viewer_site_ids()
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select m.site_id from public.memberships m
  where m.user_id = (select auth.uid()) and m.role = 'izleyici' and m.ended_on is null
$$;
revoke execute on function public.my_viewer_site_ids() from public, anon;
grant execute on function public.my_viewer_site_ids() to authenticated;

do $$
declare
  p record;
  v_using text;
  v_check text;
  v_sql text;
  v_count integer := 0;
  rx_role constant text := 'has_site_role\((?:\w+\.)?site_id, (''\{[a-z,]+\}''::site_role\[\])\)';
  rx_view constant text := 'is_site_viewer\((?:\w+\.)?site_id\)';
begin
  for p in
    select schemaname, tablename, policyname, qual, with_check
    from pg_policies
    where schemaname = 'public'
      and (coalesce(qual, '') ~ (rx_role || '|' || rx_view) or coalesce(with_check, '') ~ (rx_role || '|' || rx_view))
  loop
    v_using := regexp_replace(regexp_replace(p.qual, rx_role, '(site_id in (select public.my_site_ids(\1)))', 'g'),
                              rx_view, '(site_id in (select public.my_viewer_site_ids()))', 'g');
    v_check := regexp_replace(regexp_replace(p.with_check, rx_role, '(site_id in (select public.my_site_ids(\1)))', 'g'),
                              rx_view, '(site_id in (select public.my_viewer_site_ids()))', 'g');
    v_sql := format('alter policy %I on %I.%I', p.policyname, p.schemaname, p.tablename);
    if v_using is not null then v_sql := v_sql || format(' using (%s)', v_using); end if;
    if v_check is not null then v_sql := v_sql || format(' with check (%s)', v_check); end if;
    execute v_sql;
    v_count := v_count + 1;
  end loop;
  raise notice 'Hızlandırılan güvenlik kuralı: %', v_count;
end;
$$;

-- Sık kullanılan aramalar için dizinler
create index if not exists payments_site on public.payments (site_id) where status = 'aktif';
create index if not exists payments_unit on public.payments (unit_id) where status = 'aktif';
create index if not exists dues_unit_active on public.dues (unit_id, period, due_date) where status = 'aktif';
create index if not exists cash_entries_site_date on public.cash_entries (site_id, entry_date);
