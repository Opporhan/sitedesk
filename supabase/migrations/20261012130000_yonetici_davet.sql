-- Yönetici kendi sitesine başka yönetici ekler (kullanıcı kararı 12.10.2026): davet ve davet iptali sitenin yöneticisinde;
-- yönetici başka bir yöneticinin erişimini kapatabilir ama kendisininkini kapatamaz (site yöneticisiz kalmasın).
-- Yöneticiler birbirinin şifresini yenileyemez (create_password_reset değişmedi; sadece sistem yöneticisi).
set local lock_timeout = '15s';
set local statement_timeout = '60s';

CREATE OR REPLACE FUNCTION public.create_invite(p_site_id uuid, p_role text, p_full_name text, p_phone text, p_unit_id uuid DEFAULT NULL::uuid, p_relation text DEFAULT NULL::text)
 RETURNS TABLE(code text, token text, expires_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text;
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_expires timestamptz := now() + interval '7 days';
  v_res uuid;
begin
  if not (case p_role
            when 'sakin' then public.has_site_role(p_site_id, '{yonetici}')
            when 'danisma' then public.has_site_role(p_site_id, '{yonetici}')
            when 'yonetici' then public.has_site_role(p_site_id, '{yonetici}')
            else false end) then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if p_role = 'sakin' and not exists (select 1 from public.units where id = p_unit_id and site_id = p_site_id) then
    raise exception 'Daire bu sitede değil' using errcode = '22023';
  end if;
  update public.invites i set cancelled_at = now()
  where i.site_id = p_site_id and i.phone = p_phone and i.role = p_role and i.unit_id is not distinct from p_unit_id
    and i.used_at is null and i.cancelled_at is null;
  loop
    v_code := (select string_agg(substr(v_alphabet, 1 + (get_byte(extensions.gen_random_bytes(1), 0) % length(v_alphabet)), 1), '')
               from generate_series(1, 8));
    exit when not exists (select 1 from public.invites i where i.code = v_code);
  end loop;
  insert into public.invites (site_id, role, unit_id, relation, full_name, phone, code, token, expires_at)
  values (p_site_id, p_role, case when p_role = 'sakin' then p_unit_id end, case when p_role = 'sakin' then coalesce(p_relation, 'malik') end,
          trim(p_full_name), p_phone, v_code, v_token, v_expires);
  if p_role = 'sakin' then
    select id into v_res from public.residents where site_id = p_site_id and phone = p_phone;
    if v_res is null then
      insert into public.residents (site_id, full_name, phone) values (p_site_id, trim(p_full_name), p_phone) returning id into v_res;
    end if;
    insert into public.unit_residents (site_id, unit_id, resident_id, relation)
    values (p_site_id, p_unit_id, v_res, coalesce(p_relation, 'malik'))
    on conflict (unit_id, resident_id) where ended_on is null do nothing;
  end if;
  return query select v_code, v_token, v_expires;
end;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_invite(p_invite_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_inv public.invites;
begin
  select * into v_inv from public.invites where id = p_invite_id;
  if not found or not (public.has_site_role(v_inv.site_id, '{yonetici}')) then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  update public.invites set cancelled_at = now() where id = p_invite_id and used_at is null and cancelled_at is null;
end;
$function$;

drop policy "üyelik düzenleme" on public.memberships;
create policy "üyelik düzenleme" on public.memberships for update to authenticated
  using ((select public.is_platform_admin()) or (site_id in (select public.my_site_ids('{yonetici}'))
         and (role = 'danisma' or (role = 'yonetici' and user_id <> (select auth.uid())))))
  with check ((select public.is_platform_admin()) or (site_id in (select public.my_site_ids('{yonetici}'))
         and (role = 'danisma' or (role = 'yonetici' and user_id <> (select auth.uid())))));

drop policy "davet görme" on public.invites;
create policy "davet görme" on public.invites for select to authenticated using (
  (select public.is_platform_admin())
  or (site_id in (select public.my_site_ids('{yonetici}')) and (role in ('sakin', 'danisma', 'yonetici') or created_by = (select auth.uid())))
);
