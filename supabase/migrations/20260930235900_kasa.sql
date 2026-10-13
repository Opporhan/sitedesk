-- Adım 10: Giderler ve kasa
-- Kasa = açılış bakiyesi + aidat tahsilatları + diğer gelirler − giderler
-- Açılış bakiyesi "o gün sonu itibarıyla bankadaki para"dır: o tarihe kadarki (dahil)
-- ödemeler ve kayıtlar bakiyeye dahil sayılır, kasaya ikinci kez eklenmez.
-- Kayıtlar silinmez, iptal edilir.

create type public.cash_kind as enum ('acilis', 'gelir', 'gider');

create table public.cash_entries (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  kind public.cash_kind not null,
  category text not null check (length(trim(category)) > 0),
  description text,
  amount numeric(12, 2) not null check (amount > 0),
  entry_date date not null,
  status public.payment_status not null default 'aktif',
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users (id),
  cancel_reason text,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id)
);

-- Bir sitede tek geçerli açılış bakiyesi olur (iptal edilip yenisi girilebilir)
create unique index cash_entries_one_opening on public.cash_entries (site_id) where kind = 'acilis' and status = 'aktif';
create index on public.cash_entries (site_id, entry_date) where status = 'aktif';

revoke all on public.cash_entries from anon, authenticated;
grant select on public.cash_entries to authenticated;
grant insert (site_id, kind, category, description, amount, entry_date) on public.cash_entries to authenticated;
alter table public.cash_entries enable row level security;

create policy "kasa görme" on public.cash_entries
  for select to authenticated
  using (public.has_site_role(site_id, '{yonetici}'));

create policy "kasa kaydı ekleme" on public.cash_entries
  for insert to authenticated
  with check (
    public.has_site_role(site_id, '{yonetici}')
    and entry_date <= (now() at time zone 'Europe/Istanbul')::date
  );

create function public.cancel_cash_entry(p_entry_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
begin
  select site_id into v_site from public.cash_entries where id = p_entry_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'İptal nedeni yazılmalı' using errcode = '22023';
  end if;

  update public.cash_entries
  set status = 'iptal', cancelled_at = now(), cancelled_by = auth.uid(), cancel_reason = trim(p_reason)
  where id = p_entry_id and status = 'aktif';
  if not found then
    raise exception 'Kayıt zaten iptal edilmiş' using errcode = '22023';
  end if;
end;
$$;

revoke execute on function public.cancel_cash_entry(uuid, text) from public, anon;
grant execute on function public.cancel_cash_entry(uuid, text) to authenticated;

-- Dönem özeti. Okuyanın yetkisiyle çalışır (güvenlik kuralları geçerli).
create function public.cash_summary(p_site_id uuid, p_from date, p_to date)
returns table (opening numeric, collected numeric, other_income numeric, expenses numeric, closing numeric)
language sql stable set search_path = ''
as $$
  with start as (
    select coalesce(
      (select entry_date from public.cash_entries
       where site_id = p_site_id and kind = 'acilis' and status = 'aktif'),
      '-infinity'::date) as d
  ),
  moves as (
    -- açılış bakiyesi, girildiği aydan itibaren "ay başı kasa"ya dahil edilir
    select entry_date as d, amount as inflow, 0::numeric as outflow, 'acilis' as kind
    from public.cash_entries
    where site_id = p_site_id and kind = 'acilis' and status = 'aktif'
    union all
    select c.entry_date, case when c.kind = 'gelir' then c.amount else 0 end,
           case when c.kind = 'gider' then c.amount else 0 end, c.kind::text
    from public.cash_entries c, start
    where c.site_id = p_site_id and c.kind <> 'acilis' and c.status = 'aktif' and c.entry_date > start.d
    union all
    select p.paid_on, p.amount, 0, 'aidat'
    from public.payments p, start
    where p.site_id = p_site_id and p.status = 'aktif' and p.paid_on > start.d
  )
  select
    coalesce(sum(inflow - outflow) filter (
      where (kind = 'acilis' and d <= p_to) or (kind <> 'acilis' and d < p_from)), 0) as opening,
    coalesce(sum(inflow) filter (where d between p_from and p_to and kind = 'aidat'), 0) as collected,
    coalesce(sum(inflow) filter (where d between p_from and p_to and kind = 'gelir'), 0) as other_income,
    coalesce(sum(outflow) filter (where d between p_from and p_to), 0) as expenses,
    coalesce(sum(inflow - outflow) filter (where d <= p_to), 0) as closing
  from moves;
$$;

revoke execute on function public.cash_summary(uuid, date, date) from public, anon;
grant execute on function public.cash_summary(uuid, date, date) to authenticated;
