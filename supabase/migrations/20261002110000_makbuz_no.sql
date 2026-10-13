-- Ödeme makbuzu numarası: her sitede yıl içinde sırayla artar (2026-0001, 2026-0002 …)
-- Ödeme kaydedilirken veritabanı verir; değiştirilemez. İptal edilen ödemenin numarası boşa gitmez (makbuzu "İPTAL" görünür).

set local lock_timeout = '15s';
set local statement_timeout = '60s';

alter table public.payments
  add column receipt_year smallint,
  add column receipt_no integer;

create unique index payments_receipt_unique on public.payments (site_id, receipt_year, receipt_no);

create function public.assign_receipt_no()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  new.receipt_year := extract(year from new.paid_on)::smallint;
  perform pg_advisory_xact_lock(hashtext('makbuz-' || new.site_id::text || '-' || new.receipt_year::text));
  select coalesce(max(receipt_no), 0) + 1 into new.receipt_no
  from public.payments where site_id = new.site_id and receipt_year = new.receipt_year;
  return new;
end;
$$;

create trigger payments_receipt_no before insert on public.payments
  for each row execute function public.assign_receipt_no();

-- Mevcut ödemelere sırayla numara (kayıt sırasına göre)
with numbered as (
  select id, extract(year from paid_on)::smallint as y,
         row_number() over (partition by site_id, extract(year from paid_on) order by created_at, id) as n
  from public.payments
)
update public.payments p set receipt_year = numbered.y, receipt_no = numbered.n
from numbered where numbered.id = p.id;
