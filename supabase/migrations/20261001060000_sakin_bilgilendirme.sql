-- KVKK aydınlatması: sakinin bilgilendirildiği tarih ve yolu (whatsapp / elle)
alter table public.residents
  add column informed_at timestamptz,
  add column informed_via text check (informed_via in ('whatsapp', 'elle'));
grant update (informed_at, informed_via) on public.residents to authenticated;
