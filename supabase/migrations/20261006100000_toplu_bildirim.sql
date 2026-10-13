-- Toplu bildirim (kullanıcı kararı, 06.10.2026; Standart ve Tam pakette; sadece ücretsiz kanallar)
-- • Yönetici hedef seçer (herkes / borçlular / gecikenler / bloklar / malik-kiracı) ve duyuru ya da borç hatırlatması gönderir.
-- • Uygulama hesabı olan sakine ANINDA gider (uygulama içi mesaj + telefon bildirimi); hesabı olmayan ama telefonu olana
--   "WhatsApp turu" ile sırayla gönderilir (her biri açıldığında işaretlenir); ikisi de yoksa "ulaşılamaz" kaydedilir.
-- • Her gönderim ve kişi bazında durumu saklanır (kime gitti, kime gitmedi). Borç hatırlatmaları hatırlatma kaydına da yazılır.
-- Mevcut kayıtlar değişmez.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

create table public.bulk_sends (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  kind text not null check (kind in ('duyuru', 'hatirlatma')),
  title text not null check (length(trim(title)) between 2 and 120),
  target text not null check (length(target) <= 200), -- "Gecikenler · A, B blok" gibi
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null
);
create index on public.bulk_sends (site_id, created_at desc);

create table public.bulk_send_items (
  id uuid primary key default gen_random_uuid(),
  send_id uuid not null references public.bulk_sends (id) on delete cascade,
  site_id uuid not null references public.sites (id) on delete restrict,
  resident_id uuid not null references public.residents (id) on delete cascade,
  unit_id uuid not null references public.units (id) on delete restrict,
  channel text not null check (channel in ('uygulama', 'whatsapp', 'yok')),
  body text not null check (length(body) between 2 and 2000),
  amount numeric(12, 2) check (amount is null or amount > 0), -- hatırlatmada kişinin borç payı
  sent_at timestamptz,
  unique (send_id, resident_id, unit_id)
);
create index on public.bulk_send_items (send_id);
create index on public.bulk_send_items (site_id);

alter table public.bulk_sends enable row level security;
alter table public.bulk_send_items enable row level security;
revoke all on public.bulk_sends, public.bulk_send_items from public, anon, authenticated;
grant select on public.bulk_sends, public.bulk_send_items to authenticated;
create policy "toplu gönderim görme" on public.bulk_sends for select to authenticated
  using ((select public.has_site_role(site_id, '{yonetici}')) or (select public.is_site_viewer(site_id)));
create policy "toplu gönderim kişileri görme" on public.bulk_send_items for select to authenticated
  using ((select public.has_site_role(site_id, '{yonetici}')) or (select public.is_site_viewer(site_id)));

-- p_items: [{resident_id, unit_id, body, amount}] — metinleri uygulama hazırlar (hatırlatmada kişiye özel)
create function public.create_bulk_send(p_site_id uuid, p_kind text, p_title text, p_target text, p_items jsonb)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
  v_app boolean := public.site_has_resident_app(p_site_id);
  r jsonb;
  v_res public.residents;
  v_channel text;
  v_amount numeric;
  v_body text;
begin
  if not public.has_site_role(p_site_id, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if not v_app then
    raise exception 'Toplu bildirim Standart ve Tam pakette' using errcode = 'SD003';
  end if;
  if p_kind not in ('duyuru', 'hatirlatma') or coalesce(length(trim(p_title)), 0) not between 2 and 120 then
    raise exception 'Bildirim hatalı' using errcode = '22023';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 5000 then
    raise exception 'Alıcı listesi hatalı' using errcode = '22023';
  end if;

  insert into public.bulk_sends (site_id, kind, title, target) values (p_site_id, p_kind, trim(p_title), left(coalesce(p_target, ''), 200))
  returning id into v_id;

  for r in select * from jsonb_array_elements(p_items) loop
    select * into v_res from public.residents where id = (r->>'resident_id')::uuid and site_id = p_site_id;
    -- Sakin bu sitenin ve bu birimin aktif sakini olmalı
    if v_res.id is null or not exists (
      select 1 from public.unit_residents ur
      where ur.resident_id = v_res.id and ur.unit_id = (r->>'unit_id')::uuid and ur.ended_on is null
    ) then
      raise exception 'Alıcı bu sitenin sakini değil' using errcode = '22023';
    end if;
    v_body := left(trim(coalesce(r->>'body', '')), 2000);
    v_amount := case when p_kind = 'hatirlatma' then round((r->>'amount')::numeric, 2) end;
    if length(v_body) < 2 or (p_kind = 'hatirlatma' and coalesce(v_amount, 0) <= 0) then
      raise exception 'Alıcı metni veya tutarı hatalı' using errcode = '22023';
    end if;
    v_channel := case when v_res.user_id is not null then 'uygulama' when v_res.phone is not null then 'whatsapp' else 'yok' end;

    insert into public.bulk_send_items (send_id, site_id, resident_id, unit_id, channel, body, amount, sent_at)
    values (v_id, p_site_id, v_res.id, (r->>'unit_id')::uuid, v_channel, v_body, v_amount, case when v_channel = 'uygulama' then now() end)
    on conflict (send_id, resident_id, unit_id) do nothing;

    if v_channel = 'uygulama' and found then
      insert into public.resident_messages (site_id, resident_id, kind, title, body, url)
      values (p_site_id, v_res.id, p_kind, left(trim(p_title), 120), v_body, '/sakin');
      if p_kind = 'hatirlatma' then
        insert into public.reminders (site_id, unit_id, resident_id, amount) values (p_site_id, (r->>'unit_id')::uuid, v_res.id, v_amount);
      end if;
    end if;
  end loop;
  return v_id;
end;
$$;
revoke execute on function public.create_bulk_send(uuid, text, text, text, jsonb) from public, anon;
grant execute on function public.create_bulk_send(uuid, text, text, text, jsonb) to authenticated;

-- WhatsApp turunda bir kişinin mesajı açıldı: gönderildi say (hatırlatmaysa hatırlatma kaydına da yaz)
create function public.mark_bulk_item_sent(p_item_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_item public.bulk_send_items;
  v_kind text;
begin
  select * into v_item from public.bulk_send_items where id = p_item_id;
  if not found or not public.has_site_role(v_item.site_id, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if v_item.channel <> 'whatsapp' or v_item.sent_at is not null then
    return; -- zaten gönderildi
  end if;
  update public.bulk_send_items set sent_at = now() where id = p_item_id;
  select kind into v_kind from public.bulk_sends where id = v_item.send_id;
  if v_kind = 'hatirlatma' then
    insert into public.reminders (site_id, unit_id, resident_id, amount) values (v_item.site_id, v_item.unit_id, v_item.resident_id, v_item.amount);
  end if;
end;
$$;
revoke execute on function public.mark_bulk_item_sent(uuid) from public, anon;
grant execute on function public.mark_bulk_item_sent(uuid) to authenticated;
