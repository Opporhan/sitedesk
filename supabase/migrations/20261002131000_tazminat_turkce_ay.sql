-- Tazminat açıklamasında ay adı Türkçe olsun (veritabanı dili İngilizce: "October" yerine "Ekim")
set local lock_timeout = '15s';
set local statement_timeout = '60s';

create or replace function public.generate_late_fees(p_period date default null)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_period date := coalesce(p_period, public.current_period());
  v_from date := (v_period - interval '1 month')::date; -- geçen ayın ilk günü
  v_to date := v_period - 1;                             -- geçen ayın son günü
  v_count integer;
begin
  if extract(day from v_period) <> 1 then
    raise exception 'Dönem ayın 1''i olmalı';
  end if;

  insert into public.dues (unit_id, site_id, period, amount, due_date, kind, description, source_due_id)
  select b.unit_id, b.site_id, v_period,
         round(b.remaining * s.late_fee_rate / 100 * g.days / 30, 2),
         make_date(extract(year from v_period)::int, extract(month from v_period)::int, s.due_day),
         'tazminat',
         left(format('Gecikme tazminatı – %s (%s gün)',
                     case when b.kind = 'ek' then b.description
                          else (array['Ocak','Şubat','Mart','Nisan','Mayıs','Haziran','Temmuz','Ağustos','Eylül','Ekim','Kasım','Aralık'])[extract(month from b.period)::int]
                               || ' ' || extract(year from b.period)::int || ' aidatı' end,
                     g.days), 200),
         b.due_id
  from public.due_balances b
  join public.sites s on s.id = b.site_id and s.late_fee_enabled and s.late_fee_since is not null and s.late_fee_rate > 0
  cross join lateral (
    select (v_to - greatest(b.due_date + 1, s.late_fee_since, v_from) + 1) as days
  ) g
  where b.kind in ('aidat', 'ek')
    and b.remaining > 0
    and g.days > 0
    and round(b.remaining * s.late_fee_rate / 100 * g.days / 30, 2) > 0
    and not exists (select 1 from public.dues f where f.source_due_id = b.due_id and f.period = v_period and f.kind = 'tazminat');

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

