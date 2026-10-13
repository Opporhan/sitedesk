-- Fiyat modeli değişti (kullanıcı kararı, 05.10.2026): ücret villa/daire başına hesaplanır, paketlerde BİRİM SINIRI YOK.
-- Kullanıcı sınırı (Başlangıç 1, Standart 3, Tam sınırsız) aynen kalır. Birim ekleme ve paket değiştirme artık
-- birim sayısına takılmaz (tetikleyiciler sınır "yok" görür). Mevcut kayıtlar değişmez; geri almak için eski sınırlar geri yazılır.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

create or replace function public.package_max_units(p text)
returns integer
language sql immutable set search_path = ''
as $$ select null::integer $$;
