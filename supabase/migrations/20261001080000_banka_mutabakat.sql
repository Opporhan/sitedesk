-- Faz 1: Kasa–banka mutabakatı
-- Yönetici bankadaki gerçek bakiyeyi bir tarih için yazar; o günün sonundaki kasa tutarı
-- sistem tarafından hesaplanıp yanına kaydedilir. Kayıtlar değişmez ve silinmez (geçmiş kalır);
-- yanlış girilen kontrolün yerine yenisi girilir, en son kontrol geçerlidir.

create table public.bank_checks (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  check_date date not null,
  bank_amount numeric(14, 2) not null,
  cash_amount numeric(14, 2) not null,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null
);

create index on public.bank_checks (site_id, created_at desc);

revoke all on public.bank_checks from anon, authenticated;
grant select on public.bank_checks to authenticated;
alter table public.bank_checks enable row level security;

create policy "mutabakat görme" on public.bank_checks
  for select to authenticated
  using (public.has_site_role(site_id, '{yonetici}'));

-- Kontrol sadece bu fonksiyonla girilir: kasa tutarını kullanıcı değil sistem yazar
create function public.record_bank_check(p_site_id uuid, p_date date, p_bank_amount numeric)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
  v_cash numeric;
begin
  if not public.has_site_role(p_site_id, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if p_date is null or p_date > (now() at time zone 'Europe/Istanbul')::date then
    raise exception 'İleri tarih girilemez' using errcode = '22023';
  end if;
  if p_bank_amount is null then
    raise exception 'Banka bakiyesi yazılmalı' using errcode = '22023';
  end if;

  select closing into v_cash from public.cash_summary(p_site_id, p_date, p_date);

  insert into public.bank_checks (site_id, check_date, bank_amount, cash_amount)
  values (p_site_id, p_date, round(p_bank_amount, 2), coalesce(v_cash, 0))
  returning id into v_id;
  return v_id;
end;
$$;

revoke execute on function public.record_bank_check(uuid, date, numeric) from public, anon;
grant execute on function public.record_bank_check(uuid, date, numeric) to authenticated;
