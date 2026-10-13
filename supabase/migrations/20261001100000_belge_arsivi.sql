-- Faz 2: Belge arşivi — kasa kayıtlarına (gider/gelir) fatura, dekont, sözleşme eklenir
-- Dosyalar gizli "belgeler" kovasında, yol: {site_id}/kasa/{kayit_id}/{dosya}. Süreli imzalı linkle açılır.
-- Kayıt başına en fazla 5 belge; sadece fotoğraf (JPEG/PNG/WebP) ve PDF, dosya başına 4 MB.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('belgeler', 'belgeler', false, 4194304, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']);

-- Yolun ilk klasörü site kimliğidir; bozuk yol için null (hata vermez)
create function public.path_site_id(p_name text)
returns uuid
language sql immutable set search_path = ''
as $$
  select case when split_part(p_name, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then split_part(p_name, '/', 1)::uuid end;
$$;

create policy "belge görme" on storage.objects
  for select to authenticated
  using (bucket_id = 'belgeler' and public.has_site_role(public.path_site_id(name), '{yonetici}'));
create policy "belge yükleme" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'belgeler' and public.has_site_role(public.path_site_id(name), '{yonetici}'));
create policy "belge silme" on storage.objects
  for delete to authenticated
  using (bucket_id = 'belgeler' and public.has_site_role(public.path_site_id(name), '{yonetici}'));

alter table public.cash_entries add constraint cash_entries_id_site_key unique (id, site_id);

create table public.cash_documents (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null,
  entry_id uuid not null,
  path text not null unique,
  file_name text not null check (length(file_name) between 1 and 200),
  mime_type text not null check (mime_type in ('image/jpeg', 'image/png', 'image/webp', 'application/pdf')),
  size_bytes integer not null check (size_bytes between 1 and 4194304),
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  foreign key (entry_id, site_id) references public.cash_entries (id, site_id) on delete restrict,
  check (path like site_id::text || '/kasa/' || entry_id::text || '/%')
);

create index on public.cash_documents (entry_id);

revoke all on public.cash_documents from anon, authenticated;
grant select, insert, delete on public.cash_documents to authenticated;
alter table public.cash_documents enable row level security;

create policy "kasa belgesi görme" on public.cash_documents
  for select to authenticated using (public.has_site_role(site_id, '{yonetici}'));
create policy "kasa belgesi ekleme" on public.cash_documents
  for insert to authenticated with check (public.has_site_role(site_id, '{yonetici}'));
create policy "kasa belgesi silme" on public.cash_documents
  for delete to authenticated using (public.has_site_role(site_id, '{yonetici}'));

-- Kayıt başına en fazla 5 belge
create function public.limit_cash_documents()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtext(new.entry_id::text));
  if (select count(*) from public.cash_documents where entry_id = new.entry_id) >= 5 then
    raise exception 'Bir kayda en fazla 5 belge eklenebilir' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger cash_documents_limit before insert on public.cash_documents
  for each row execute function public.limit_cash_documents();
