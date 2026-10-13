-- Karışık site (villa + daire): ekranlarda "Birimler" yazar, her birimin tipi görünür.
set local lock_timeout = '15s';
set local statement_timeout = '60s';

alter type public.site_type add value if not exists 'karisik';
