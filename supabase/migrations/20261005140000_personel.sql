-- Personel ve maaş takibi (kullanıcı kararı, 05.10.2026; Standart ve Tam pakette)
-- • Yönetici sitenin çalışanlarını tutar: ad, görev, telefon, aylık maaş, maaşın yazılacağı bütçe kalemi adı, başlangıç/ayrılış.
-- • "Maaşı öde" kasaya gider olarak yazılır (o yılın bütçe kalemine; açıklama "Maaş – Ad Soyad – Ekim 2026").
--   Bir çalışana aynı ay için ikinci maaş yazılmaz (iptal edilen yeniden yazılabilir). İptal kasadaki gibi.
-- • Personel kaydı silinmez; ayrılış tarihi yazılır. Danışma göremez (maaş bilgisi).
-- Mevcut kayıtlar değişmez.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

create table public.staff (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  full_name text not null check (length(trim(full_name)) between 3 and 100),
  job text check (job is null or length(job) <= 100),
  phone text check (phone is null or phone ~ '^90\d{10}$'),
  salary numeric(12, 2) check (salary is null or salary > 0),
  budget_item_name text check (budget_item_name is null or length(budget_item_name) <= 200),
  started_on date not null default (now() at time zone 'Europe/Istanbul')::date,
  ended_on date,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  unique (id, site_id),
  check (ended_on is null or ended_on >= started_on)
);
create index on public.staff (site_id);

alter table public.staff enable row level security;
revoke all on public.staff from public, anon, authenticated;
grant select on public.staff to authenticated;
grant insert (site_id, full_name, job, phone, salary, budget_item_name, started_on) on public.staff to authenticated;
grant update (full_name, job, phone, salary, budget_item_name, started_on, ended_on) on public.staff to authenticated;
create policy "personel görme" on public.staff for select to authenticated
  using ((select public.has_site_role(site_id, '{yonetici}')) or (select public.is_site_viewer(site_id)));
create policy "personel ekleme" on public.staff for insert to authenticated
  with check ((select public.has_site_role(site_id, '{yonetici}')));
create policy "personel düzenleme" on public.staff for update to authenticated
  using ((select public.has_site_role(site_id, '{yonetici}')))
  with check ((select public.has_site_role(site_id, '{yonetici}')));

-- Maaş ödemesi = kasa gider kaydı + hangi çalışanın hangi ayı
alter table public.cash_entries add column staff_id uuid, add column salary_period date check (salary_period is null or extract(day from salary_period) = 1);
alter table public.cash_entries add constraint cash_entries_staff_fk foreign key (staff_id, site_id) references public.staff (id, site_id);
alter table public.cash_entries add constraint cash_entries_salary_pair check ((staff_id is null) = (salary_period is null));
create unique index cash_entries_one_salary on public.cash_entries (staff_id, salary_period) where staff_id is not null and status = 'aktif';

create function public.pay_salary(p_staff_id uuid, p_period date, p_amount numeric, p_paid_on date, p_budget_item_id uuid)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_staff public.staff;
  v_item text;
  v_id uuid;
  v_months text[] := array['Ocak','Şubat','Mart','Nisan','Mayıs','Haziran','Temmuz','Ağustos','Eylül','Ekim','Kasım','Aralık'];
begin
  select * into v_staff from public.staff where id = p_staff_id;
  if not found or not public.has_site_role(v_staff.site_id, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if p_amount is null or round(p_amount, 2) <= 0 or p_amount >= 100000000 then
    raise exception 'Tutar hatalı' using errcode = '22023';
  end if;
  if p_paid_on is null or p_paid_on > (now() at time zone 'Europe/Istanbul')::date then
    raise exception 'Ödeme tarihi ileri bir tarih olamaz' using errcode = '22023';
  end if;
  if p_period is null or extract(day from p_period) <> 1 then
    raise exception 'Maaş ayı hatalı' using errcode = '22023';
  end if;
  -- Gider kategorisi = sitenin ödeme yılındaki bütçe kalemi
  select i.name into v_item
  from public.budget_items i join public.budgets b on b.id = i.budget_id
  where i.id = p_budget_item_id and i.site_id = v_staff.site_id and b.year = extract(year from p_paid_on);
  if v_item is null then
    raise exception 'Bütçe kalemi bulunamadı (ödeme yılının kalemi olmalı)' using errcode = '22023';
  end if;
  if exists (select 1 from public.cash_entries where staff_id = p_staff_id and salary_period = p_period and status = 'aktif') then
    raise exception 'Bu ayın maaşı zaten yazılmış' using errcode = '23505';
  end if;

  insert into public.cash_entries (site_id, kind, category, budget_item_id, description, amount, entry_date, staff_id, salary_period)
  values (v_staff.site_id, 'gider', v_item, p_budget_item_id,
          'Maaş – ' || v_staff.full_name || ' – ' || v_months[extract(month from p_period)::int] || ' ' || extract(year from p_period),
          round(p_amount, 2), p_paid_on, p_staff_id, p_period)
  returning id into v_id;

  -- Bir sonraki ödemede aynı kalem önerilsin
  update public.staff set budget_item_name = v_item where id = p_staff_id and budget_item_name is distinct from v_item;
  return v_id;
end;
$$;
revoke execute on function public.pay_salary(uuid, date, numeric, date, uuid) from public, anon;
grant execute on function public.pay_salary(uuid, date, numeric, date, uuid) to authenticated;
