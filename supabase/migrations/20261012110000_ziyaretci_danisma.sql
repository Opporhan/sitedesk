-- Ziyaretçi de sadece danışmanın ve sakinin işi (kullanıcı kararı 12.10.2026): ziyaretçiyi sadece sitenin DANIŞMASI kaydeder/görür,
-- sakin kendi evine geleni görür. Yönetici ve sistem yöneticisi ziyaretçileri, sayılarını ve işlem geçmişini görmez (kargodaki gibi).
set local lock_timeout = '15s';
set local statement_timeout = '60s';

drop policy "ziyaretçi görme" on public.visitors;
create policy "ziyaretçi görme" on public.visitors for select to authenticated
  using (public.is_desk(site_id) or public.resident_can_see(unit_id, arrived_at, true));

CREATE OR REPLACE FUNCTION public.delete_visitor(p_visitor_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_v public.visitors;
begin
  select * into v_v from public.visitors where id = p_visitor_id for update;
  if v_v.id is null or not public.is_desk(v_v.site_id) then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if not public.is_today_tr(v_v.arrived_at) then raise exception 'Sadece bugün girilen kayıt silinebilir' using errcode = '22023'; end if;
  delete from public.visitors where id = p_visitor_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.mark_visitor_departed(p_visitor_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_v public.visitors;
begin
  select * into v_v from public.visitors where id = p_visitor_id for update;
  if v_v.id is null or not public.is_desk(v_v.site_id) then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if v_v.departed_at is not null then return; end if;
  update public.visitors set departed_at = now(), departed_by = auth.uid() where id = p_visitor_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.record_visitor(p_client_id uuid, p_unit_id uuid, p_name text, p_plate text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_site uuid; v_id uuid; v_plate text;
begin
  select id into v_id from public.visitors where client_id = p_client_id;
  if v_id is not null then return v_id; end if;
  select site_id into v_site from public.units where id = p_unit_id;
  if v_site is null or not public.is_desk(v_site) then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  -- Plaka büyük harf, boşluk/tire atılır ("34 abc 123" → "34ABC123")
  v_plate := nullif(regexp_replace(upper(coalesce(p_plate, '')), '[^0-9A-ZÇĞİÖŞÜ]', '', 'g'), '');
  insert into public.visitors (site_id, unit_id, client_id, visitor_name, plate) values (v_site, p_unit_id, p_client_id, trim(p_name), v_plate)
  returning id into v_id;
  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.undo_visitor_departure(p_visitor_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_v public.visitors;
begin
  select * into v_v from public.visitors where id = p_visitor_id for update;
  if v_v.id is null or not public.is_desk(v_v.site_id) then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if v_v.departed_at is null or not public.is_today_tr(v_v.departed_at) then raise exception 'Sadece bugünkü çıkış geri alınabilir' using errcode = '22023'; end if;
  update public.visitors set departed_at = null, departed_by = null where id = p_visitor_id;
end;
$function$;

drop policy "geçmiş görme" on public.audit_log;
create policy "geçmiş görme" on public.audit_log for select to authenticated
  using (site_id in (select public.my_site_ids('{yonetici}')) and entity not in ('packages', 'visitors'));

create or replace function public.my_sites_overview()
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
      'new_tickets', (select count(*) from public.tickets t where t.site_id = s.id and t.status = 'alindi')
    ) as x
    from public.sites s
    where s.id in (select public.my_site_ids('{yonetici}'))
  ) q
$$;
