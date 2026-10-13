-- Kargo sadeleşti (kullanıcı isteği): firma seçilmez; villaya dokun → kaydet ve sakine haber ver.
-- Yanlış villaya girilen kargo aynı gün (teslim edilmediyse) silinebilir.

alter table public.packages alter column carrier drop not null;

create function public.delete_package(p_package_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
begin
  select site_id into v_site from public.packages where id = p_package_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici,danisma}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  delete from public.packages
  where id = p_package_id
    and delivered_at is null
    and (received_at at time zone 'Europe/Istanbul')::date = (now() at time zone 'Europe/Istanbul')::date;
  if not found then
    raise exception 'Sadece bugün girilen ve teslim edilmemiş kargo silinebilir' using errcode = '22023';
  end if;
end;
$$;

revoke execute on function public.delete_package(uuid) from public, anon;
grant execute on function public.delete_package(uuid) to authenticated;
