-- Belge yolu mutlaka bir site klasörüyle başlamalı (sistem yöneticisi dahil)
drop policy "belge görme" on storage.objects;
drop policy "belge yükleme" on storage.objects;
drop policy "belge silme" on storage.objects;

create policy "belge görme" on storage.objects
  for select to authenticated
  using (bucket_id = 'belgeler' and public.path_site_id(name) is not null
         and public.has_site_role(public.path_site_id(name), '{yonetici}'));
create policy "belge yükleme" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'belgeler' and public.path_site_id(name) is not null
              and public.has_site_role(public.path_site_id(name), '{yonetici}'));
create policy "belge silme" on storage.objects
  for delete to authenticated
  using (bucket_id = 'belgeler' and public.path_site_id(name) is not null
         and public.has_site_role(public.path_site_id(name), '{yonetici}'));
