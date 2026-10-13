-- Hafızaya "varsa güncelle, yoksa ekle" (upsert) için gerekli güncelleme izni; kural gereği sadece site yöneticisi
grant update (site_id, match_key) on public.bank_rules to authenticated;
