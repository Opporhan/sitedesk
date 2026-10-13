-- Adım 8: Sakin "Ödeme yaptım" bildirimi, dekont deposu, sadece havale

-- ---------------------------------------------------------------
-- Ödeme şekli sadece Havale/EFT
-- ---------------------------------------------------------------
alter table public.payments add constraint payments_only_havale check (method = 'havale');

-- ---------------------------------------------------------------
-- "Ödeme yaptım" bildirimleri
-- ---------------------------------------------------------------
create type public.notice_status as enum ('bekliyor', 'islendi', 'reddedildi');

create table public.payment_notices (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null,
  site_id uuid not null,
  user_id uuid not null default auth.uid() references public.profiles (user_id),
  amount numeric(12, 2) not null check (amount > 0),
  paid_on date not null,
  note text,
  receipt_path text,
  status public.notice_status not null default 'bekliyor',
  payment_id uuid references public.payments (id),
  handled_at timestamptz,
  handled_by uuid references auth.users (id),
  reject_reason text,
  created_at timestamptz not null default now(),
  foreign key (unit_id, site_id) references public.units (id, site_id) on delete restrict
);

create index on public.payment_notices (site_id) where status = 'bekliyor';
create index on public.payment_notices (unit_id);

revoke all on public.payment_notices from anon, authenticated;
grant select on public.payment_notices to authenticated;
-- Sakin sadece bu alanları doldurabilir; durum ve işleyen bilgisi fonksiyonla değişir
grant insert (unit_id, site_id, amount, paid_on, note, receipt_path) on public.payment_notices to authenticated;
alter table public.payment_notices enable row level security;

create policy "bildirim görme" on public.payment_notices
  for select to authenticated
  using (
    (select public.is_platform_admin())
    or public.has_site_role(site_id, '{yonetici}')
    or public.is_unit_resident(unit_id)
  );

create policy "sakin bildirim gönderir" on public.payment_notices
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and public.is_unit_resident(unit_id)
    and paid_on <= (now() at time zone 'Europe/Istanbul')::date
    and (receipt_path is null or receipt_path like site_id::text || '/' || unit_id::text || '/%')
  );

-- ---------------------------------------------------------------
-- Ödeme kaydı: bildirimden geliyorsa bildirimi "işlendi" yapar (aynı işlemde)
-- ---------------------------------------------------------------
drop function public.record_payment(uuid, numeric, date, public.payment_method, text);

create function public.record_payment(
  p_unit_id uuid, p_amount numeric, p_paid_on date, p_note text default null, p_notice_id uuid default null
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

  insert into public.payments (unit_id, site_id, amount, paid_on, method, note)
  values (p_unit_id, v_site, round(p_amount, 2), p_paid_on, 'havale', nullif(trim(p_note), ''))
  returning id into v_id;

  if p_notice_id is not null then
    update public.payment_notices
    set status = 'islendi', payment_id = v_id, handled_at = now(), handled_by = auth.uid()
    where id = p_notice_id and unit_id = p_unit_id and status = 'bekliyor';
    if not found then
      raise exception 'Bildirim bulunamadı veya zaten işlenmiş' using errcode = '22023';
    end if;
  end if;

  return v_id;
end;
$$;

create function public.reject_payment_notice(p_notice_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
begin
  select site_id into v_site from public.payment_notices where id = p_notice_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Ret nedeni yazılmalı' using errcode = '22023';
  end if;

  update public.payment_notices
  set status = 'reddedildi', reject_reason = trim(p_reason), handled_at = now(), handled_by = auth.uid()
  where id = p_notice_id and status = 'bekliyor';
  if not found then
    raise exception 'Bildirim zaten işlenmiş' using errcode = '22023';
  end if;
end;
$$;

revoke execute on function public.record_payment(uuid, numeric, date, text, uuid) from public, anon;
revoke execute on function public.reject_payment_notice(uuid, text) from public, anon;
grant execute on function public.record_payment(uuid, numeric, date, text, uuid) to authenticated;
grant execute on function public.reject_payment_notice(uuid, text) to authenticated;

-- ---------------------------------------------------------------
-- Dekont deposu (gizli). Dosya yolu: {site_id}/{unit_id}/{dosya}
-- ---------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'receipts', 'receipts', false, 4194304,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif', 'application/pdf']
);

-- Yol "{site}/{ev}/..." biçiminde mi ve ev o sitenin mi?
create function public.receipt_path_parts(p_name text, out site_id uuid, out unit_id uuid)
language plpgsql stable security definer set search_path = ''
as $$
declare
  parts text[] := storage.foldername(p_name);
begin
  site_id := parts[1]::uuid;
  unit_id := parts[2]::uuid;
  if not exists (select 1 from public.units u where u.id = unit_id and u.site_id = receipt_path_parts.site_id) then
    site_id := null; unit_id := null;
  end if;
exception when others then
  site_id := null; unit_id := null;
end;
$$;

create function public.can_upload_receipt(p_name text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select p.unit_id is not null and public.is_unit_resident(p.unit_id)
  from public.receipt_path_parts(p_name) p;
$$;

create function public.can_read_receipt(p_name text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select p.unit_id is not null and (
    public.is_platform_admin()
    or public.has_site_role(p.site_id, '{yonetici}')
    or public.is_unit_resident(p.unit_id)
  )
  from public.receipt_path_parts(p_name) p;
$$;

revoke execute on function public.receipt_path_parts(text) from public, anon, authenticated;
revoke execute on function public.can_upload_receipt(text) from public, anon;
revoke execute on function public.can_read_receipt(text) from public, anon;
grant execute on function public.can_upload_receipt(text) to authenticated;
grant execute on function public.can_read_receipt(text) to authenticated;

create policy "dekont yükleme" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'receipts' and public.can_upload_receipt(name));

create policy "dekont görme" on storage.objects
  for select to authenticated
  using (bucket_id = 'receipts' and public.can_read_receipt(name));
