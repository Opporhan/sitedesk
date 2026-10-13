-- Yönetici kendi sitesini açar (kullanıcı kararı 08.10.2026): en az bir sitede aktif yönetici olan kişi yeni site açabilir;
-- açan kişi o sitenin yöneticisi olur, site 30 gün deneme süresiyle (paid_until) açılır, sistem yöneticisine bildirim gider.
-- Sistem yöneticisi de bu fonksiyonla açar (kendisi üye olmaz, süre yazılmaz). Günde en fazla 10 site.
create function public.create_site(p_name text, p_type public.site_type, p_address text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
  v_admin boolean := public.is_platform_admin();
begin
  if auth.uid() is null or not (v_admin or exists (
       select 1 from public.memberships m join public.sites s on s.id = m.site_id
       where m.user_id = auth.uid() and m.role = 'yonetici' and m.ended_on is null and s.active)) then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_name, ''))) < 2 then raise exception 'Site adını yazın' using errcode = '22023'; end if;
  if not v_admin and (select count(*) from public.sites where created_by = auth.uid() and created_at > now() - interval '1 day') >= 10 then
    raise exception 'Bugün çok fazla site açtınız' using errcode = 'SD050';
  end if;
  insert into public.sites (name, type, address, paid_until)
  values (left(trim(p_name), 80), p_type, nullif(left(trim(coalesce(p_address, '')), 200), ''), case when v_admin then null else current_date + 30 end)
  returning id into v_id;
  if not v_admin then
    insert into public.memberships (user_id, site_id, role) values (auth.uid(), v_id, 'yonetici');
    perform public.notify_users((select array_agg(user_id) from public.platform_admins), 'Yeni site açıldı',
      left(trim(p_name), 80) || ' · ' || coalesce(public.my_name(), 'Yönetici') || ' (30 gün deneme)', '/');
  end if;
  return v_id;
end;
$$;
revoke execute on function public.create_site(text, public.site_type, text) from public, anon;
grant execute on function public.create_site(text, public.site_type, text) to authenticated;
