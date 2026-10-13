-- Adım 10 düzeltme: Açılış bakiyesi "o gün BAŞI itibarıyla" sayılır.
-- Açılış gününün kendisindeki ödeme, gelir ve giderler kasaya eklenir;
-- sadece önceki günlerin kayıtları açılış bakiyesine dahil sayılır.

create or replace function public.cash_summary(p_site_id uuid, p_from date, p_to date)
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
    where c.site_id = p_site_id and c.kind <> 'acilis' and c.status = 'aktif' and c.entry_date >= start.d
    union all
    select p.paid_on, p.amount, 0, 'aidat'
    from public.payments p, start
    where p.site_id = p_site_id and p.status = 'aktif' and p.paid_on >= start.d
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
