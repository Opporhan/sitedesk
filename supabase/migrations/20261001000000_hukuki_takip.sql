-- Adım 11: Hukuki takip işareti (villa/daire üzerinde)
-- Uzun süre ödemeyen daire "hukuki takipte" olarak işaretlenir; icra işleminin kendisi avukatta yürür.
-- Yetki: mevcut "ev yönetimi" kuralı (site yöneticisi / sistem yöneticisi) geçerlidir.

alter table public.units
  add column legal_since date,
  add column legal_note text;
