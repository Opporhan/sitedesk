-- Faz 3.2: Ziyaretçi girişi (kullanıcı kararı: personel girişi yok, sadece ziyaretçi)
-- Danışma sakini arayıp onay alır, sonra yazar: villa, ziyaretçi adı, isteğe bağlı plaka. Çıkış tutulmaz.
-- KVKK: kayıtlar 1 yıl sonra her gece kendiliğinden silinir.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

create table public.visitors (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null,
  unit_id uuid not null,
  visitor_name text not null check (length(trim(visitor_name)) between 2 and 100),
  plate text check (plate is null or plate ~ '^[0-9A-ZÇĞİÖŞÜ]{2,12}$'),
  arrived_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  foreign key (unit_id, site_id) references public.units (id, site_id) on delete restrict
);

create index on public.visitors (site_id, arrived_at desc);

revoke all on public.visitors from anon, authenticated;
grant select on public.visitors to authenticated;
grant insert (site_id, unit_id, visitor_name, plate) on public.visitors to authenticated;
alter table public.visitors enable row level security;

create policy "ziyaretçi görme" on public.visitors
  for select to authenticated using (public.has_site_role(site_id, '{yonetici,danisma}'));
create policy "ziyaretçi kaydı" on public.visitors
  for insert to authenticated with check (public.has_site_role(site_id, '{yonetici,danisma}'));

-- Yanlış kayıt aynı gün silinebilir
create function public.delete_visitor(p_visitor_id uuid)
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
  delete from public.visitors
  where id = p_visitor_id
    and (arrived_at at time zone 'Europe/Istanbul')::date = (now() at time zone 'Europe/Istanbul')::date;
  if not found then
    raise exception 'Sadece bugünkü kayıt silinebilir' using errcode = '22023';
  end if;
end;
$$;

revoke execute on function public.delete_visitor(uuid) from public, anon;
grant execute on function public.delete_visitor(uuid) to authenticated;

-- 1 yıldan eski ziyaretçi kayıtları her gece silinir
create function public.purge_old_visitors()
returns integer
language sql security definer set search_path = ''
as $$
  with gone as (delete from public.visitors where arrived_at < now() - interval '1 year' returning 1)
  select count(*)::integer from gone;
$$;

revoke execute on function public.purge_old_visitors() from public, anon, authenticated;

select cron.schedule('ziyaretci-temizlik', '30 1 * * *', $$select public.purge_old_visitors()$$);
