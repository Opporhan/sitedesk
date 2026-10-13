-- Geçmiş borç aktarımı (devir): uygulamaya geçmeden önceki dönemden kalan borçlar birim başına tek satır olarak girilir.
-- • Aynı borç tablosunda kind = 'devir' (açıklama "Önceki dönemden devreden borç"); ödeme dağıtımı, borçlular,
--   hatırlatma, hesap dökümü ve makbuz kendiliğinden görür. Aidat istatistiklerine ve gecikme tazminatına girmez.
-- • Bir birimde tek geçerli devir olur; yanlışsa iptal edilip yeniden girilir.
-- • Sadece sistem yöneticisi girer (aidat tutarı ve ek ücret gibi); tek işlem: ya hepsi ya hiçbiri.
-- Mevcut kayıtlar değişmez.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

alter table public.dues drop constraint dues_kind_check;
alter table public.dues add constraint dues_kind_check check (kind in ('aidat', 'ek', 'tazminat', 'devir'));

create unique index dues_one_carryover on public.dues (unit_id) where kind = 'devir' and status = 'aktif';

-- p_rows: [{unit_id, amount}] · p_date: devrin tarihi (uygulamaya geçiş günü; borç bu tarihte vadesi gelmiş sayılır)
create function public.import_opening_debts(p_site_id uuid, p_rows jsonb, p_date date, p_description text default null)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  r jsonb;
  v_unit uuid;
  v_amount numeric;
  v_label text;
  v_line integer := 0;
  v_desc text := coalesce(nullif(trim(p_description), ''), 'Önceki dönemden devreden borç');
begin
  if not public.is_platform_admin() then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if p_date is null or p_date > (now() at time zone 'Europe/Istanbul')::date then
    raise exception 'Devir tarihi ileri bir tarih olamaz' using errcode = '22023';
  end if;
  if length(v_desc) not between 3 and 200 then
    raise exception 'Açıklama 3-200 karakter olmalı' using errcode = '22023';
  end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 or jsonb_array_length(p_rows) > 5000 then
    raise exception 'Satır listesi hatalı' using errcode = '22023';
  end if;

  for r in select * from jsonb_array_elements(p_rows) loop
    v_line := v_line + 1;
    v_unit := nullif(r->>'unit_id', '')::uuid;
    v_amount := round((r->>'amount')::numeric, 2);
    select b.name || u.no into v_label
    from public.units u join public.blocks b on b.id = u.block_id
    where u.id = v_unit and u.site_id = p_site_id;
    if v_label is null then
      raise exception '%. satır: birim bu siteye ait değil', v_line using errcode = '22023';
    end if;
    if v_amount is null or v_amount <= 0 or v_amount >= 100000000 then
      raise exception '%. satır (%): tutar hatalı', v_line, v_label using errcode = '22023';
    end if;
    if exists (select 1 from public.dues where unit_id = v_unit and kind = 'devir' and status = 'aktif') then
      raise exception '%: devreden borç zaten girilmiş; önce iptal edin', v_label using errcode = '23505';
    end if;

    insert into public.dues (unit_id, site_id, period, amount, due_date, kind, description)
    values (v_unit, p_site_id, date_trunc('month', p_date)::date, v_amount, p_date, 'devir', v_desc);
    perform public.recalc_late_fees(v_unit, p_date);
  end loop;
  return v_line;
end;
$$;

revoke execute on function public.import_opening_debts(uuid, jsonb, date, text) from public, anon;
grant execute on function public.import_opening_debts(uuid, jsonb, date, text) to authenticated;
