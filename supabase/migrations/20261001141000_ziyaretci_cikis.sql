-- Ziyaretçi çıkışı (kullanıcı isteği): "Çıkış yaptı" butonu o anki saati kendiliğinden yazar.
-- Yanlışlıkla basılırsa aynı gün geri alınır.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

alter table public.visitors
  add column departed_at timestamptz,
  add column departed_by uuid references auth.users (id) on delete set null,
  add constraint visitors_departed_after_arrival check (departed_at is null or departed_at >= arrived_at);

create index on public.visitors (site_id) where departed_at is null;

create function public.mark_visitor_departed(p_visitor_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
begin
  select site_id into v_site from public.visitors where id = p_visitor_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici,danisma}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  update public.visitors set departed_at = now(), departed_by = auth.uid()
  where id = p_visitor_id and departed_at is null;
  if not found then
    raise exception 'Bu ziyaretçinin çıkışı zaten yazılmış' using errcode = '22023';
  end if;
end;
$$;

create function public.undo_visitor_departure(p_visitor_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
begin
  select site_id into v_site from public.visitors where id = p_visitor_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici,danisma}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  update public.visitors set departed_at = null, departed_by = null
  where id = p_visitor_id
    and (departed_at at time zone 'Europe/Istanbul')::date = (now() at time zone 'Europe/Istanbul')::date;
  if not found then
    raise exception 'Sadece bugün yazılan çıkış geri alınabilir' using errcode = '22023';
  end if;
end;
$$;

revoke execute on function public.mark_visitor_departed(uuid) from public, anon;
revoke execute on function public.undo_visitor_departure(uuid) from public, anon;
grant execute on function public.mark_visitor_departed(uuid) to authenticated;
grant execute on function public.undo_visitor_departure(uuid) to authenticated;
