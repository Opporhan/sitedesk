-- Gün 1: Bütçe (işletme projesi)
-- Her site için yıllık bütçe: gruplar (A. Personel, B. Destek ve ofis, …) ve kalemler.
-- Kalemin yıllık tutarı saklanır; aylık = yıllık ÷ 12 (işletme projelerindeki hesapla aynı).
-- Giderler (kasa kayıtları) ileride bir bütçe kalemine bağlanır.

create table public.budgets (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  year smallint not null check (year between 2000 and 2100),
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id),
  unique (site_id, year),
  unique (id, site_id)
);

create table public.budget_items (
  id uuid primary key default gen_random_uuid(),
  budget_id uuid not null,
  site_id uuid not null,
  group_code text not null check (group_code ~ '^[A-Z]$'),
  group_name text not null check (length(trim(group_name)) > 0),
  name text not null check (length(trim(name)) > 0),
  annual_amount numeric(14, 2) not null default 0 check (annual_amount >= 0),
  sort smallint not null default 0,
  created_at timestamptz not null default now(),
  foreign key (budget_id, site_id) references public.budgets (id, site_id) on delete cascade,
  unique (id, site_id)
);

create index on public.budget_items (budget_id, group_code, sort);

-- Gider kaydı bir bütçe kalemine bağlanabilir (aynı sitenin kalemi olmak zorunda)
alter table public.cash_entries add column budget_item_id uuid;
alter table public.cash_entries
  add constraint cash_entries_budget_item_fkey
  foreign key (budget_item_id, site_id) references public.budget_items (id, site_id) on delete restrict;
create index on public.cash_entries (budget_item_id) where budget_item_id is not null;
grant insert (budget_item_id) on public.cash_entries to authenticated;

-- Yetkiler: site yöneticisi (ve her sitede sistem yöneticisi) görür ve düzenler
revoke all on public.budgets, public.budget_items from anon, authenticated;
grant select, insert on public.budgets to authenticated;
grant select, insert, delete on public.budget_items to authenticated;
grant update (group_name, name, annual_amount, sort) on public.budget_items to authenticated;
alter table public.budgets enable row level security;
alter table public.budget_items enable row level security;

create policy "bütçe görme" on public.budgets
  for select to authenticated using (public.has_site_role(site_id, '{yonetici}'));
create policy "bütçe ekleme" on public.budgets
  for insert to authenticated with check (public.has_site_role(site_id, '{yonetici}'));

create policy "bütçe kalemi görme" on public.budget_items
  for select to authenticated using (public.has_site_role(site_id, '{yonetici}'));
create policy "bütçe kalemi yönetimi" on public.budget_items
  for all to authenticated
  using (public.has_site_role(site_id, '{yonetici}'))
  with check (public.has_site_role(site_id, '{yonetici}'));

-- Yeni bütçe: standart gruplar ve kalemler (tutarlar 0) ya da önceki yılın kopyası
create function public.create_budget(p_site_id uuid, p_year smallint)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
  v_prev uuid;
begin
  if not public.has_site_role(p_site_id, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;

  insert into public.budgets (site_id, year) values (p_site_id, p_year) returning id into v_id;

  select id into v_prev from public.budgets where site_id = p_site_id and year = p_year - 1;
  if v_prev is not null then
    insert into public.budget_items (budget_id, site_id, group_code, group_name, name, annual_amount, sort)
    select v_id, site_id, group_code, group_name, name, annual_amount, sort
    from public.budget_items where budget_id = v_prev;
  else
    insert into public.budget_items (budget_id, site_id, group_code, group_name, name, sort)
    select v_id, p_site_id, g, gn, n, s
    from (values
      ('A', 'Personel Giderleri', 'Personel maaşı', 1),
      ('A', 'Personel Giderleri', 'Sigorta maliyeti', 2),
      ('A', 'Personel Giderleri', 'Resmi tatil payları', 3),
      ('A', 'Personel Giderleri', 'Zorunlu İSG mali mesuliyet', 4),
      ('A', 'Personel Giderleri', 'Yönetim hizmet bedeli', 5),
      ('B', 'Destek Hizmet ve Ofis Giderleri', 'Temizlik ve hijyen sarf malzeme giderleri', 1),
      ('B', 'Destek Hizmet ve Ofis Giderleri', 'Ofis kırtasiye sarf malzeme giderleri', 2),
      ('B', 'Destek Hizmet ve Ofis Giderleri', 'Mali müşavirlik hizmeti', 3),
      ('B', 'Destek Hizmet ve Ofis Giderleri', 'Noter ve posta masrafı', 4),
      ('B', 'Destek Hizmet ve Ofis Giderleri', 'Muhasebe programı', 5),
      ('C', 'Enerji ve Su Giderleri', 'Ortak alan elektrik kullanım gideri', 1),
      ('C', 'Enerji ve Su Giderleri', 'Ortak alan su kullanım gideri', 2),
      ('C', 'Enerji ve Su Giderleri', 'Doğalgaz', 3),
      ('C', 'Enerji ve Su Giderleri', 'Jeneratör yakıt gideri', 4),
      ('D', 'Bakım Onarım Giderleri', 'Asansör bakım gideri ve yıllık kontrol ücreti', 1),
      ('D', 'Bakım Onarım Giderleri', 'Peyzaj bakım gideri', 2),
      ('D', 'Bakım Onarım Giderleri', 'Periyodik bakım giderleri (jeneratör, hidrofor, yangın, havalandırma)', 3),
      ('D', 'Bakım Onarım Giderleri', 'Havuz bakım, analiz ve kimyasal gideri', 4),
      ('D', 'Bakım Onarım Giderleri', 'Mekanik elektrik sarf malzeme giderleri', 5),
      ('D', 'Bakım Onarım Giderleri', 'Pest kontrol giderleri', 6),
      ('E', 'Diğer Giderler', 'Öngörülemeyen giderler', 1)
    ) as t(g, gn, n, s);
  end if;
  return v_id;
end;
$$;

revoke execute on function public.create_budget(uuid, smallint) from public, anon;
grant execute on function public.create_budget(uuid, smallint) to authenticated;
