-- Yeni site kurulum rehberi: hangi adımda kalındığı (yarıda bırakılırsa oradan devam). Boş = kurulum bitti.
-- Adımlar: 2 Bloklar · 3 Birimler · 4 Aidat · 5 Sakinler · 6 Kasa açılışı · 7 Danışma (1 = site bilgileri, oluşturunca geçilir)
set local lock_timeout = '15s';
set local statement_timeout = '60s';

alter table public.sites add column setup_step smallint check (setup_step is null or setup_step between 2 and 7);

create function public.set_setup_step(p_site_id uuid, p_step smallint)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  update public.sites set setup_step = p_step where id = p_site_id;
end;
$$;

revoke execute on function public.set_setup_step(uuid, smallint) from public, anon;
grant execute on function public.set_setup_step(uuid, smallint) to authenticated;
