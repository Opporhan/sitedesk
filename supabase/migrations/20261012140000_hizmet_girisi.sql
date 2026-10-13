-- Ziyaretçi türü (kullanıcı kararı 12.10.2026): danışma girişte "misafir" (sakinin misafiri) ya da "hizmet" (tamir, servis,
-- teknisyen, temizlik vb.) seçer. Yönetici sadece HİZMET girişlerini görür; sakinlerin misafirlerini göremez.
-- Sakin kendi evine gelen her iki türü de görür (değişmedi). Danışma hepsini görür.
set local lock_timeout = '15s';
set local statement_timeout = '60s';

alter table public.visitors add column kind text not null default 'misafir' check (kind in ('misafir', 'hizmet'));

drop policy "ziyaretçi görme" on public.visitors;
create policy "ziyaretçi görme" on public.visitors for select to authenticated using (
  public.is_desk(site_id)
  or (kind = 'hizmet' and site_id in (select public.my_site_ids('{yonetici}')))
  or public.resident_can_see(unit_id, arrived_at, true)
);

drop function public.record_visitor(uuid, uuid, text, text);
create function public.record_visitor(p_client_id uuid, p_unit_id uuid, p_name text, p_plate text default null, p_kind text default 'misafir')
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_site uuid; v_id uuid; v_plate text;
begin
  select id into v_id from public.visitors where client_id = p_client_id;
  if v_id is not null then return v_id; end if;
  select site_id into v_site from public.units where id = p_unit_id;
  if v_site is null or not public.is_desk(v_site) then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if coalesce(p_kind, 'misafir') not in ('misafir', 'hizmet') then raise exception 'Giriş türü hatalı' using errcode = '22023'; end if;
  -- Plaka büyük harf, boşluk/tire atılır ("34 abc 123" → "34ABC123")
  v_plate := nullif(regexp_replace(upper(coalesce(p_plate, '')), '[^0-9A-ZÇĞİÖŞÜ]', '', 'g'), '');
  insert into public.visitors (site_id, unit_id, client_id, visitor_name, plate, kind)
  values (v_site, p_unit_id, p_client_id, trim(p_name), v_plate, coalesce(p_kind, 'misafir'))
  returning id into v_id;
  return v_id;
end;
$$;
revoke execute on function public.record_visitor(uuid, uuid, text, text, text) from public, anon;
grant execute on function public.record_visitor(uuid, uuid, text, text, text) to authenticated;
