-- Kargo sadece danışmanın ve sakinin işi (kullanıcı kararı 08.10.2026):
-- • Kargoyu sadece sitenin DANIŞMASI kaydeder, görür, teslim eder; sakin sadece kendi dairesine geleni görür.
--   Yönetici ve sistem yöneticisi kargoyu GÖRMEZ (sistem yöneticisi de ancak o sitede danışma üyesiyse görür).
--   Kargo işlemleri yöneticinin işlem geçmişinde de görünmez.
-- • Danışma bekleyen kargo için sakine "Kargonuz danışmada bekliyor" bildirimi tekrar gönderebilir (aynı kargoya saatte bir).
-- • Ziyaretçiler değişmez: yönetici "içeride kim var" görmeye devam eder.
set local lock_timeout = '15s';
set local statement_timeout = '60s';

-- Danışma mı? (sadece gerçek, aktif danışma üyeliği; sistem yöneticisine otomatik yetki YOK)
create function public.is_desk(p_site_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.memberships m join public.sites s on s.id = m.site_id
                 where m.user_id = (select auth.uid()) and m.site_id = p_site_id and m.role = 'danisma' and m.ended_on is null and s.active)
$$;
revoke execute on function public.is_desk(uuid) from public, anon;
grant execute on function public.is_desk(uuid) to authenticated;

drop policy "kargo görme" on public.packages;
create policy "kargo görme" on public.packages for select to authenticated
  using (public.is_desk(site_id) or public.resident_can_see(unit_id, received_at, false));

alter table public.packages add column reminded_at timestamptz;

create or replace function public.record_package(p_client_id uuid, p_unit_id uuid, p_note text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_site uuid; v_id uuid;
begin
  select id into v_id from public.packages where client_id = p_client_id;
  if v_id is not null then return v_id; end if;
  select site_id into v_site from public.units where id = p_unit_id;
  if v_site is null or not public.is_desk(v_site) then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  insert into public.packages (site_id, unit_id, client_id, note) values (v_site, p_unit_id, p_client_id, nullif(left(trim(coalesce(p_note, '')), 200), ''))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.deliver_package(p_package_id uuid, p_to text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_p public.packages;
begin
  select * into v_p from public.packages where id = p_package_id for update;
  if v_p.id is null or not public.is_desk(v_p.site_id) then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if v_p.delivered_at is not null then return; end if; -- iki kez teslim olmaz
  update public.packages set delivered_at = now(), delivered_by = auth.uid(), delivered_to = nullif(left(trim(coalesce(p_to, '')), 100), '') where id = p_package_id;
end;
$$;

create or replace function public.undo_package_delivery(p_package_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_p public.packages;
begin
  select * into v_p from public.packages where id = p_package_id for update;
  if v_p.id is null or not public.is_desk(v_p.site_id) then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if v_p.delivered_at is null or not public.is_today_tr(v_p.delivered_at) then raise exception 'Sadece bugün yapılan teslim geri alınabilir' using errcode = '22023'; end if;
  update public.packages set delivered_at = null, delivered_by = null, delivered_to = null where id = p_package_id;
end;
$$;

create or replace function public.delete_package(p_package_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_p public.packages;
begin
  select * into v_p from public.packages where id = p_package_id for update;
  if v_p.id is null or not public.is_desk(v_p.site_id) then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if v_p.delivered_at is not null or not public.is_today_tr(v_p.received_at) then raise exception 'Sadece bugün girilen, teslim edilmemiş kargo silinebilir' using errcode = '22023'; end if;
  delete from public.packages where id = p_package_id;
end;
$$;

-- Bekleyen kargo için sakine yeniden haber ver (aynı kargoya saatte en fazla bir kez)
create function public.remind_package(p_package_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_p public.packages;
begin
  select * into v_p from public.packages where id = p_package_id for update;
  if v_p.id is null or not public.is_desk(v_p.site_id) then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if v_p.delivered_at is not null then raise exception 'Kargo teslim edilmiş' using errcode = '22023'; end if;
  if v_p.reminded_at > now() - interval '1 hour' then raise exception 'Bu kargo için az önce haber verildi' using errcode = 'SD030'; end if;
  update public.packages set reminded_at = now() where id = p_package_id;
  perform public.notify_users(public.unit_resident_users(v_p.unit_id), 'Kargonuz danışmada bekliyor',
    public.unit_label(v_p.unit_id) || ' adına gelen kargonuz danışmada. Danışmadan teslim alabilirsiniz.', '/sakin/kargo');
end;
$$;
revoke execute on function public.remind_package(uuid) from public, anon;
grant execute on function public.remind_package(uuid) to authenticated;

-- İşlem geçmişi: kargo kayıtları yöneticiye gösterilmez
drop policy "geçmiş görme" on public.audit_log;
create policy "geçmiş görme" on public.audit_log for select to authenticated
  using (site_id in (select public.my_site_ids('{yonetici}')) and entity <> 'packages');

-- Sitelerim: bekleyen kargo sayısı çıkarıldı (yönetici kargoyu görmez)
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
      'new_tickets', (select count(*) from public.tickets t where t.site_id = s.id and t.status = 'alindi'),
      'inside_visitors', (select count(*) from public.visitors v where v.site_id = s.id and v.departed_at is null and v.arrived_at > now() - interval '7 days')
    ) as x
    from public.sites s
    where s.id in (select public.my_site_ids('{yonetici}'))
  ) q
$$;
