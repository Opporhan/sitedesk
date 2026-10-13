-- Adım 8c: Sistem yöneticisi bütün sitelerde site yöneticisi yetkisine sahiptir.
-- Bütün kurallar has_site_role() üzerinden kontrol edildiği için tek değişiklik yeterli:
-- site yöneticisi (veya danışma) yetkisi istenen her yerde sistem yöneticisi de geçer.

create or replace function public.has_site_role(p_site_id uuid, p_roles public.site_role[])
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.is_platform_admin()
      or exists (
        select 1 from public.memberships
        where user_id = (select auth.uid()) and site_id = p_site_id
          and role = any (p_roles) and ended_on is null
      );
$$;
