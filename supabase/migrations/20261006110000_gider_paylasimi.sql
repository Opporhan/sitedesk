-- Merkezi ısınma ve ortak sayaç (su) paylaşımı (kullanıcı kararı, 06.10.2026; Standart ve Tam pakette)
-- • Yönetici dönemin faturasını (toplam tutar) ve her birimin sayaç / ısı pay ölçer okumasını (ilk–son endeks) girer.
-- • Paylaşım yönetmeliğe uygun ve seçmeli: toplamın SABİT kısmı (%30 varsayılan; pay ölçer yoksa %100) m²'ye veya eşit,
--   kalanı TÜKETİME (son − ilk endeks) göre dağıtılır. Tüketim toplamı sıfırsa hepsi sabit dayanağa göre.
--   Kuruş farkı en büyük paya eklenir; birimlerin toplamı faturaya kuruşu kuruşuna eşittir.
-- • Önizleme ve borca yazma aynı fonksiyondan (cost_split_lines): ekrandaki rakam = yazılan borç.
-- • "Borçlara yaz" her birime ayrı borç satırı yazar (dues.kind = 'paylasim', açıklama "Ekim 2026 ısınma payı").
--   Ödeme dağıtımı, borçlular, hatırlatma, makbuz, sakin uygulaması kendiliğinden görür; gecikme tazminatı işlemez.
-- • Aynı tür ve dönem için tek geçerli paylaşım; iptal edilince borçları da nedeniyle iptal olur. Danışma göremez.
-- Mevcut kayıtlar değişmez.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

-- Birimin net alanı (m²)
alter table public.units add column area_m2 numeric(8, 2) check (area_m2 is null or area_m2 > 0);
grant select (area_m2) on public.units to authenticated;

create table public.cost_splits (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  kind text not null check (kind in ('isinma', 'su')),
  period date not null check (extract(day from period) = 1),
  total numeric(12, 2) not null check (total > 0),
  fixed_pct numeric(5, 2) not null default 30 check (fixed_pct between 0 and 100),
  fixed_basis text not null default 'm2' check (fixed_basis in ('m2', 'esit')),
  due_date date not null,
  status text not null default 'taslak' check (status in ('taslak', 'uygulandi', 'iptal')),
  applied_at timestamptz,
  cancel_reason text,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null
);
create unique index cost_splits_one_per_period on public.cost_splits (site_id, kind, period) where status <> 'iptal';
create index on public.cost_splits (site_id, period desc);

create table public.cost_split_readings (
  split_id uuid not null references public.cost_splits (id) on delete cascade,
  site_id uuid not null references public.sites (id) on delete restrict,
  unit_id uuid not null references public.units (id) on delete restrict,
  prev_index numeric(14, 3) not null check (prev_index >= 0),
  curr_index numeric(14, 3) not null check (curr_index >= prev_index),
  primary key (split_id, unit_id)
);
create index on public.cost_split_readings (site_id);

alter table public.cost_splits enable row level security;
alter table public.cost_split_readings enable row level security;
revoke all on public.cost_splits, public.cost_split_readings from public, anon, authenticated;
grant select on public.cost_splits, public.cost_split_readings to authenticated;
create policy "paylaşım görme" on public.cost_splits for select to authenticated
  using ((select public.has_site_role(site_id, '{yonetici}')) or (select public.is_site_viewer(site_id)));
create policy "paylaşım okuması görme" on public.cost_split_readings for select to authenticated
  using ((select public.has_site_role(site_id, '{yonetici}')) or (select public.is_site_viewer(site_id)));

-- Borç türü: gider paylaşımı
alter table public.dues drop constraint dues_kind_check;
alter table public.dues add constraint dues_kind_check check (kind in ('aidat', 'ek', 'tazminat', 'devir', 'paylasim'));
alter table public.dues add column split_id uuid references public.cost_splits (id) on delete restrict;
create index dues_split on public.dues (split_id) where split_id is not null;
alter table public.cost_splits add constraint cost_splits_id_site unique (id, site_id);

-- Taslak kaydet (yeni veya mevcut taslak). p_readings: [{unit_id, prev, curr}] — okuma girilmeyen birimin tüketimi 0 sayılır
create function public.save_cost_split(
  p_site_id uuid, p_split_id uuid, p_kind text, p_period date, p_total numeric, p_fixed_pct numeric, p_fixed_basis text,
  p_due_date date, p_readings jsonb
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid := p_split_id;
  r jsonb;
begin
  if not public.has_site_role(p_site_id, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if not public.site_has_resident_app(p_site_id) then
    raise exception 'Gider paylaşımı Standart ve Tam pakette' using errcode = 'SD003';
  end if;
  if p_kind not in ('isinma', 'su') or p_period is null or extract(day from p_period) <> 1 or p_due_date is null
     or p_total is null or round(p_total, 2) <= 0 or p_total >= 100000000
     or p_fixed_pct is null or p_fixed_pct not between 0 and 100 or p_fixed_basis not in ('m2', 'esit') then
    raise exception 'Paylaşım bilgileri hatalı' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_readings, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_readings, '[]'::jsonb)) > 5000 then
    raise exception 'Okumalar hatalı' using errcode = '22023';
  end if;

  if v_id is null then
    insert into public.cost_splits (site_id, kind, period, total, fixed_pct, fixed_basis, due_date)
    values (p_site_id, p_kind, p_period, round(p_total, 2), p_fixed_pct, p_fixed_basis, p_due_date)
    returning id into v_id;
  else
    update public.cost_splits
    set kind = p_kind, period = p_period, total = round(p_total, 2), fixed_pct = p_fixed_pct, fixed_basis = p_fixed_basis, due_date = p_due_date
    where id = v_id and site_id = p_site_id and status = 'taslak';
    if not found then
      raise exception 'Sadece taslak paylaşım değiştirilebilir' using errcode = '22023';
    end if;
    delete from public.cost_split_readings where split_id = v_id;
  end if;

  for r in select * from jsonb_array_elements(coalesce(p_readings, '[]'::jsonb)) loop
    if not exists (select 1 from public.units where id = (r->>'unit_id')::uuid and site_id = p_site_id) then
      raise exception 'Okuma bu sitenin birimine ait değil' using errcode = '22023';
    end if;
    if (r->>'curr')::numeric < (r->>'prev')::numeric then
      raise exception 'Son endeks ilk endeksten küçük olamaz' using errcode = '22023';
    end if;
    insert into public.cost_split_readings (split_id, site_id, unit_id, prev_index, curr_index)
    values (v_id, p_site_id, (r->>'unit_id')::uuid, (r->>'prev')::numeric, (r->>'curr')::numeric);
  end loop;
  return v_id;
end;
$$;
revoke execute on function public.save_cost_split(uuid, uuid, text, date, numeric, numeric, text, date, jsonb) from public, anon;
grant execute on function public.save_cost_split(uuid, uuid, text, date, numeric, numeric, text, date, jsonb) to authenticated;

-- Paylaşımın birim birim sonucu (önizleme ve borca yazma aynı hesabı kullanır)
create function public.cost_split_lines(p_split_id uuid)
returns table (unit_id uuid, label text, area numeric, consumption numeric, fixed_share numeric, variable_share numeric, amount numeric)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v public.cost_splits;
  v_fixed numeric;
  v_var numeric;
  v_area numeric;
  v_cons numeric;
  v_count integer;
begin
  select * into v from public.cost_splits where id = p_split_id;
  if not found or not (public.has_site_role(v.site_id, '{yonetici}') or public.is_site_viewer(v.site_id)) then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  v_fixed := round(v.total * v.fixed_pct / 100, 2);
  v_var := v.total - v_fixed;
  select coalesce(sum(u.area_m2), 0), count(*) into v_area, v_count from public.units u where u.site_id = v.site_id;
  select coalesce(sum(curr_index - prev_index), 0) into v_cons from public.cost_split_readings where split_id = p_split_id;
  -- Tüketim yoksa değişken kısım da sabit dayanağa göre
  if v_cons = 0 then
    v_fixed := v.total;
    v_var := 0;
  end if;

  return query
  with base as (
    select u.id as unit_id, b.name || '-' || u.no as label, u.area_m2 as area,
           coalesce(rd.curr_index - rd.prev_index, 0) as consumption,
           case when v.fixed_basis = 'm2' then
                  case when v_area > 0 then v_fixed * coalesce(u.area_m2, 0) / v_area else 0 end
                else v_fixed / nullif(v_count, 0) end as fixed_raw,
           case when v_cons > 0 then v_var * coalesce(rd.curr_index - rd.prev_index, 0) / v_cons else 0 end as var_raw
    from public.units u
    join public.blocks b on b.id = u.block_id
    left join public.cost_split_readings rd on rd.split_id = p_split_id and rd.unit_id = u.id
    where u.site_id = v.site_id
  ),
  rounded as (
    select *, round(fixed_raw + var_raw, 2) as amt from base
  ),
  diff as (
    select v.total - coalesce(sum(amt), 0) as d from rounded
  ),
  top as (
    select r.unit_id from rounded r order by r.amt desc, r.label limit 1
  )
  select r.unit_id, r.label, r.area, r.consumption, round(r.fixed_raw, 2), round(r.var_raw, 2),
         r.amt + case when r.unit_id = (select t.unit_id from top t) then (select d from diff) else 0 end
  from rounded r
  order by r.label;
end;
$$;
revoke execute on function public.cost_split_lines(uuid) from public, anon;
grant execute on function public.cost_split_lines(uuid) to authenticated;

-- Borçlara yaz: her birime bir borç satırı. m² dayanağında alanı girilmemiş birim varsa yazılmaz.
create function public.apply_cost_split(p_split_id uuid)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v public.cost_splits;
  v_count integer;
  v_months text[] := array['Ocak','Şubat','Mart','Nisan','Mayıs','Haziran','Temmuz','Ağustos','Eylül','Ekim','Kasım','Aralık'];
  v_desc text;
begin
  select * into v from public.cost_splits where id = p_split_id for update;
  if not found or not public.has_site_role(v.site_id, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if v.status <> 'taslak' then
    raise exception 'Bu paylaşım zaten borçlara yazılmış veya iptal edilmiş' using errcode = '22023';
  end if;
  if v.fixed_basis = 'm2' and v.fixed_pct > 0 and exists (select 1 from public.units where site_id = v.site_id and area_m2 is null) then
    raise exception 'm² ile paylaşım için bütün birimlerin alanı girilmeli' using errcode = '22023';
  end if;
  v_desc := v_months[extract(month from v.period)::int] || ' ' || extract(year from v.period) || ' '
            || case v.kind when 'isinma' then 'ısınma payı' else 'su payı' end;

  insert into public.dues (unit_id, site_id, period, amount, due_date, kind, description, split_id)
  select l.unit_id, v.site_id, v.period, l.amount, v.due_date, 'paylasim', v_desc, v.id
  from public.cost_split_lines(p_split_id) l
  where l.amount > 0;
  get diagnostics v_count = row_count;

  update public.cost_splits set status = 'uygulandi', applied_at = now() where id = p_split_id;
  return v_count;
end;
$$;
revoke execute on function public.apply_cost_split(uuid) from public, anon;
grant execute on function public.apply_cost_split(uuid) to authenticated;

-- İptal: taslak ise sadece iptal; borçlara yazılmışsa borçları da aynı nedenle iptal edilir
create function public.cancel_cost_split(p_split_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v public.cost_splits;
  d record;
begin
  select * into v from public.cost_splits where id = p_split_id;
  if not found or not public.has_site_role(v.site_id, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'İptal nedeni yazılmalı' using errcode = '22023';
  end if;
  if v.status = 'iptal' then
    raise exception 'Paylaşım zaten iptal edilmiş' using errcode = '22023';
  end if;
  for d in select id from public.dues where split_id = p_split_id and status = 'aktif' loop
    perform public.cancel_due(d.id, trim(p_reason));
  end loop;
  update public.cost_splits set status = 'iptal', cancel_reason = trim(p_reason) where id = p_split_id;
end;
$$;
revoke execute on function public.cancel_cost_split(uuid, text) from public, anon;
grant execute on function public.cancel_cost_split(uuid, text) to authenticated;
