-- Excel'den yüklenen sakinde taşınma tarihi boş bırakılabilir (kullanıcı kararı, 02.10.2026).
-- Boşsa tarih olarak kayıt günü yazılır (süre gösterimi için) ama "taşınma tarihi bilinmiyor" işaretlenir:
-- böyle bir kiracı birimin mevcut bütün açık borçlarından sorumlu sayılır (hatırlatmalar ona da gider).
-- Tarih sonradan düzeltilirse işaret kendiliğinden kalkar. Mevcut kayıtlar değişmez.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

alter table public.unit_residents add column start_unknown boolean not null default false;

create function public.unit_resident_start_known()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if new.started_on is distinct from old.started_on then
    new.start_unknown := false;
  end if;
  return new;
end;
$$;

create trigger start_known before update on public.unit_residents
  for each row execute function public.unit_resident_start_known();

create or replace function public.import_directory(p_site_id uuid, p_rows jsonb)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_site_type public.site_type;
  v_type public.unit_type;
  r jsonb;
  v_block uuid; v_unit uuid; v_resident uuid;
  v_name text; v_phone text; v_no text; v_block_name text;
  c_blocks int := 0; c_units int := 0; c_residents int := 0; c_existing int := 0; c_links int := 0; c_skipped int := 0;
begin
  if not public.has_site_role(p_site_id, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 2000 then
    raise exception 'En fazla 2000 satır yüklenebilir' using errcode = '22023';
  end if;
  select type into v_site_type from public.sites where id = p_site_id;

  for r in select * from jsonb_array_elements(p_rows) loop
    v_block_name := upper(trim(r->>'block'));
    v_no := trim(r->>'no');
    if coalesce(v_block_name, '') = '' or coalesce(v_no, '') = '' or length(v_block_name) > 20 or length(v_no) > 20 then
      raise exception 'Blok veya numara hatalı: %', r using errcode = '22023';
    end if;

    select id into v_block from public.blocks where site_id = p_site_id and name = v_block_name;
    if v_block is null then
      insert into public.blocks (site_id, name) values (p_site_id, v_block_name) returning id into v_block;
      c_blocks := c_blocks + 1;
    end if;

    select id into v_unit from public.units where block_id = v_block and no = v_no;
    if v_unit is null then
      v_type := case
        when r->>'type' in ('villa', 'daire') then (r->>'type')::public.unit_type
        when v_site_type = 'villa' then 'villa'::public.unit_type
        when v_site_type = 'apartman' then 'daire'::public.unit_type
      end;
      if v_type is null then
        raise exception 'Karışık sitede yeni birimin tipi (Villa/Daire) yazılmalı: %', r using errcode = '22023';
      end if;
      insert into public.units (site_id, block_id, no, type) values (p_site_id, v_block, v_no, v_type) returning id into v_unit;
      c_units := c_units + 1;
    end if;

    v_name := nullif(trim(r->>'full_name'), '');
    if v_name is null then
      continue;
    end if;
    v_phone := nullif(r->>'phone', '');

    v_resident := null;
    if v_phone is not null then
      select id into v_resident from public.residents where site_id = p_site_id and phone = v_phone;
    else
      select res.id into v_resident
      from public.residents res join public.unit_residents ur on ur.resident_id = res.id
      where ur.unit_id = v_unit and ur.ended_on is null and lower(res.full_name) = lower(v_name)
      limit 1;
    end if;
    if v_resident is null then
      insert into public.residents (site_id, full_name, phone) values (p_site_id, v_name, v_phone) returning id into v_resident;
      c_residents := c_residents + 1;
    else
      c_existing := c_existing + 1;
    end if;

    if exists (select 1 from public.unit_residents where unit_id = v_unit and resident_id = v_resident and ended_on is null) then
      c_skipped := c_skipped + 1;
    else
      -- Taşınma tarihi boşsa kayıt günü yazılır ama "bilinmiyor" işaretlenir (hatırlatmada birimin bütün borçları)
      insert into public.unit_residents (unit_id, site_id, resident_id, relation, started_on, start_unknown)
      values (v_unit, p_site_id, v_resident,
              coalesce(nullif(r->>'relation', ''), 'malik')::public.resident_relation,
              least(coalesce(nullif(r->>'started_on', '')::date, (now() at time zone 'Europe/Istanbul')::date),
                    (now() at time zone 'Europe/Istanbul')::date),
              nullif(r->>'started_on', '') is null);
      c_links := c_links + 1;
    end if;
  end loop;

  return jsonb_build_object('blocks', c_blocks, 'units', c_units, 'residents', c_residents,
                            'existing', c_existing, 'links', c_links, 'skipped', c_skipped);
end;
$$;
