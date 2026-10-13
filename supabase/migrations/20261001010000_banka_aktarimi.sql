-- Adım 12: Banka hareketlerinden ödeme aktarımı
-- Bankadan gelen her hareketin bir kimliği (bank_ref) olur; aynı hareket ikinci kez ödeme olarak kaydedilemez.
-- (Ödeme iptal edilirse aynı hareket yeniden aktarılabilir.)

alter table public.payments add column bank_ref text;
create unique index payments_bank_ref_unique on public.payments (site_id, bank_ref) where bank_ref is not null and status = 'aktif';

drop function public.record_payment(uuid, numeric, date, text);

create function public.record_payment(
  p_unit_id uuid, p_amount numeric, p_paid_on date, p_note text default null, p_bank_ref text default null
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
  v_id uuid;
begin
  select site_id into v_site from public.units where id = p_unit_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Tutar sıfırdan büyük olmalı' using errcode = '22023';
  end if;
  if p_paid_on is null or p_paid_on > (now() at time zone 'Europe/Istanbul')::date then
    raise exception 'Ödeme tarihi ileri bir tarih olamaz' using errcode = '22023';
  end if;

  insert into public.payments (unit_id, site_id, amount, paid_on, method, note, bank_ref)
  values (p_unit_id, v_site, round(p_amount, 2), p_paid_on, 'havale', nullif(trim(p_note), ''), nullif(trim(p_bank_ref), ''))
  returning id into v_id;
  return v_id;
end;
$$;

revoke execute on function public.record_payment(uuid, numeric, date, text, text) from public, anon;
grant execute on function public.record_payment(uuid, numeric, date, text, text) to authenticated;
