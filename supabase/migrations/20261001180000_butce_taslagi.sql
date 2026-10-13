-- Gelecek yılın bütçe taslağı: bu yılın kalemleri × (1 + artış oranı)
-- Oranı kullanıcı girer (sistem enflasyon tahmin etmez). Tek işlem: ya hepsi oluşur ya hiçbiri.
-- Daire başı aidat yazılmaz (bütçe sayfası öneri gösterir; kullanıcı belirler).

set local lock_timeout = '15s';
set local statement_timeout = '60s';

create function public.create_budget_draft(p_site_id uuid, p_year smallint, p_rate numeric)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_from uuid;
  v_id uuid;
begin
  if not public.has_site_role(p_site_id, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if p_rate is null or p_rate < -50 or p_rate > 500 then
    raise exception 'Artış oranı -50 ile 500 arasında olmalı' using errcode = '22023';
  end if;
  select id into v_from from public.budgets where site_id = p_site_id and year = p_year;
  if v_from is null then
    raise exception '% bütçesi yok', p_year using errcode = '22023';
  end if;

  insert into public.budgets (site_id, year) values (p_site_id, p_year + 1) returning id into v_id;
  insert into public.budget_items (budget_id, site_id, group_code, group_name, name, annual_amount, sort)
  select v_id, site_id, group_code, group_name, name, round(annual_amount * (1 + p_rate / 100), 2), sort
  from public.budget_items where budget_id = v_from;
  return v_id;
end;
$$;

revoke execute on function public.create_budget_draft(uuid, smallint, numeric) from public, anon;
grant execute on function public.create_budget_draft(uuid, smallint, numeric) to authenticated;
