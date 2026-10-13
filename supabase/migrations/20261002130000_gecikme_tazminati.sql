-- Gecikme tazminatı (isteğe bağlı, site ayarı; varsayılan kapalı). Kullanıcı kararları (02.10.2026):
-- • Gün hesabıyla: kalan borç × aylık oran × gecikilen gün ÷ 30 (KMK m.20: "geciktirdiği günler için aylık %5").
-- • Aidat ve ek ücretlere işler; tazminata tazminat işlemez.
-- • Ödeme önce asıl borçlara, tazminat satırları en sona sayılır.
-- • Sadece açıldığı tarihten sonraki gecikme günleri; geçmişe dönük çalışmaz.
-- Her ayın 1'inde geçen ayın gecikme günleri için borç başına ayrı satır (kind = 'tazminat') yazılır;
-- aynı borç + ay için ikinci satır yazılmaz, iptal edilen tekrar yazılmaz.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

alter table public.sites
  add column late_fee_enabled boolean not null default false,
  add column late_fee_rate numeric(4, 2) check (late_fee_rate is null or (late_fee_rate > 0 and late_fee_rate <= 5)),
  add column late_fee_since date;

alter table public.dues drop constraint dues_kind_check;
alter table public.dues add constraint dues_kind_check check (kind in ('aidat', 'ek', 'tazminat'));
alter table public.dues add column source_due_id uuid references public.dues (id) on delete restrict;
alter table public.dues add constraint dues_fee_has_source check ((kind = 'tazminat') = (source_due_id is not null));
create unique index dues_one_fee_per_month on public.dues (source_due_id, period) where kind = 'tazminat';

-- Ödeme dağıtımı: önce asıl borçlar (en eskiden), tazminat satırları en sonda
create or replace view public.due_balances with (security_invoker = true) as
  with d as (
    select dues.id, dues.unit_id, dues.site_id, dues.period, dues.amount, dues.due_date, dues.kind, dues.description,
           sum(dues.amount) over (partition by dues.unit_id
                                  order by (dues.kind = 'tazminat'), dues.period, dues.due_date, dues.id) as cumulative
    from public.dues
    where dues.status = 'aktif'
  ), p as (
    select payments.unit_id, sum(payments.amount) as paid
    from public.payments
    where payments.status = 'aktif'
    group by payments.unit_id
  ), x as (
    select d.*, least(d.amount, greatest(0::numeric, coalesce(p.paid, 0) - (d.cumulative - d.amount))) as paid_amount
    from d left join p using (unit_id)
  )
  select id as due_id, unit_id, site_id, period, amount, due_date, paid_amount,
         amount - paid_amount as remaining,
         case when paid_amount >= amount then 'odendi' when paid_amount > 0 then 'kismi' else 'odenmedi' end as payment_state,
         (amount - paid_amount > 0 and due_date < (now() at time zone 'Europe/Istanbul')::date) as overdue,
         kind, description
  from x;

-- Ayar: sadece sistem yöneticisi. Açılınca "açılış tarihi" bugündür (kapalıyken açılırsa yenilenir).
create function public.set_late_fee(p_site_id uuid, p_enabled boolean, p_rate numeric)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if p_enabled and (p_rate is null or p_rate <= 0 or p_rate > 5) then
    raise exception 'Oran 0 ile 5 arasında olmalı (yasal üst sınır aylık %%5)' using errcode = '22023';
  end if;
  update public.sites
  set late_fee_enabled = p_enabled,
      late_fee_rate = case when p_enabled then round(p_rate, 2) else late_fee_rate end,
      late_fee_since = case
        when p_enabled and not late_fee_enabled then (now() at time zone 'Europe/Istanbul')::date
        when p_enabled then late_fee_since
        else null end
  where id = p_site_id;
end;
$$;

revoke execute on function public.set_late_fee(uuid, boolean, numeric) from public, anon;
grant execute on function public.set_late_fee(uuid, boolean, numeric) to authenticated;

-- Tazminat yazımı: p_period ayının 1'inde, bir önceki ayın gecikme günleri için. Tekrar çalışması zararsız.
create function public.generate_late_fees(p_period date default null)
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
                          else to_char(b.period, 'TMMonth YYYY') || ' aidatı' end,
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

revoke execute on function public.generate_late_fees(date) from public, anon, authenticated;

select cron.schedule('gecikme-tazminati', '15 * 1 * *', $$select public.generate_late_fees()$$);
