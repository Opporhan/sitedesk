-- Para denetimi (02.10.2026): çift kayıt açıkları kapatılır. Mevcut hiçbir kayıt değişmez.
-- 1) Aynı ödeme art arda iki kez kaydedilemez (çift tıklama, aynı anda iki istek).
-- 2) Aynı banka hareketi hem ödeme hem kasa kaydı olamaz (önceden her tablo sadece kendi içinde kontrol ediyordu).
-- 3) Aynı ek ücret aynı birime iki kez yazılamaz.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

-- ---------------------------------------------------------------
-- 1) Ödeme: çift kayıt koruması
-- Elle girilen (banka kimliği olmayan) ödemede aynı kişi aynı villaya aynı tutarı aynı tarihle
-- yarım dakika içinde ikinci kez kaydedemez. Bankadan aktarılanları banka kimliği korur.
-- ---------------------------------------------------------------
create or replace function public.record_payment(
  p_unit_id uuid, p_amount numeric, p_paid_on date, p_note text default null, p_bank_ref text default null
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
  v_id uuid;
  v_ref text := nullif(trim(p_bank_ref), '');
begin
  select site_id into v_site from public.units where id = p_unit_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if p_amount is null or round(p_amount, 2) <= 0 then
    raise exception 'Tutar sıfırdan büyük olmalı' using errcode = '22023';
  end if;
  if p_paid_on is null or p_paid_on > (now() at time zone 'Europe/Istanbul')::date then
    raise exception 'Ödeme tarihi ileri bir tarih olamaz' using errcode = '22023';
  end if;

  if v_ref is null then
    -- Aynı villaya aynı anda gelen iki istek sıraya girer; ikincisi birincinin kaydını görür
    perform pg_advisory_xact_lock(hashtext('odeme-' || p_unit_id::text));
    if exists (
      select 1 from public.payments
      where unit_id = p_unit_id and status = 'aktif' and bank_ref is null
        and amount = round(p_amount, 2) and paid_on = p_paid_on
        and created_by is not distinct from auth.uid()
        and created_at > now() - interval '30 seconds'
    ) then
      raise exception 'Bu ödeme az önce kaydedildi' using errcode = 'SD001';
    end if;
  end if;

  insert into public.payments (unit_id, site_id, amount, paid_on, method, note, bank_ref)
  values (p_unit_id, v_site, round(p_amount, 2), p_paid_on, 'havale', nullif(trim(p_note), ''), v_ref)
  returning id into v_id;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------
-- 2) Banka hareketi: ödemeler ve kasa kayıtları birlikte tek kimlik
-- ---------------------------------------------------------------
create function public.bank_ref_once()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_taken boolean;
begin
  if new.bank_ref is null or new.status <> 'aktif' then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtext('banka-' || new.site_id::text || '-' || new.bank_ref));
  if tg_table_name = 'payments' then
    select exists (select 1 from public.cash_entries where site_id = new.site_id and bank_ref = new.bank_ref and status = 'aktif') into v_taken;
  else
    select exists (select 1 from public.payments where site_id = new.site_id and bank_ref = new.bank_ref and status = 'aktif') into v_taken;
  end if;
  if v_taken then
    raise exception 'Bu banka hareketi zaten kaydedilmiş' using errcode = '23505';
  end if;
  return new;
end;
$$;

revoke execute on function public.bank_ref_once() from public, anon, authenticated;

create trigger bank_ref_once before insert on public.payments
  for each row execute function public.bank_ref_once();
create trigger bank_ref_once before insert on public.cash_entries
  for each row execute function public.bank_ref_once();

-- ---------------------------------------------------------------
-- 3) Ek ücret: aynı açıklama + aynı son ödeme tarihi bir birime bir kez (iptal edilen yeniden yazılabilir)
-- ---------------------------------------------------------------
create unique index dues_one_extra on public.dues (unit_id, due_date, description) where kind = 'ek' and status = 'aktif';
