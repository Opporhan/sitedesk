-- Sakin hesapları (kullanıcı kararı, 05.10.2026; her pakette): sakin uygulamaya TELEFON + ŞİFRE ile girer.
-- • Giriş hesabı Supabase Auth'ta, telefondan türetilen iç e-postayla tutulur (sakin-905321234567@sakin.sitedesk.invalid);
--   bu adrese hiçbir e-posta gönderilmez. İlk (geçici) şifreyi yönetici üretir; sakin ilk girişte kendi şifresini belirler.
-- • residents.user_id: rehber kaydının giriş hesabı. Sakin verisini tablolardan doğrudan OKUYAMAZ; her şey
--   kendi kaydına bağlı güvenlik fonksiyonlarından gelir (my_home). Kiracı sadece taşınmasından sonraki dönemi görür.
-- • Sakine giden her bilgi (ödeme alındı, hatırlatma, kargo, arıza, duyuru) uygulama içi mesajdır (resident_messages);
--   telefonuna bildirim (push) sunucu tarafından ayrıca gönderilir. Hesabı olmayan sakine WhatsApp ile devam edilir.
-- Mevcut kayıtlar değişmez.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

alter table public.residents add column user_id uuid references auth.users (id) on delete set null;
create unique index residents_site_user_unique on public.residents (site_id, user_id) where user_id is not null;
create index on public.residents (user_id) where user_id is not null;

alter table public.residents drop constraint residents_informed_via_check;
alter table public.residents add constraint residents_informed_via_check check (informed_via in ('whatsapp', 'elle', 'uygulama'));

-- Telefonun giriş adresi (tek yer; uygulamada lib/resident-account.ts aynısını kullanır)
create function public.resident_login_email(p_phone text)
returns text
language sql immutable set search_path = ''
as $$ select 'sakin-' || p_phone || '@sakin.sitedesk.invalid' $$;

-- Türkçe para: 4.000,00 ₺
create function public.tr_money(p numeric)
returns text
language sql immutable set search_path = ''
as $$ select translate(to_char(p, 'FM999,999,999,990.00'), ',.', '.,') || ' ₺' $$;

-- Hesap açma/şifre yenileme öncesi kontrol (sunucu, giriş hesabını açmadan önce sorar): yönetici mi, telefon var mı?
create function public.resident_account_phone(p_resident_id uuid)
returns text
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_site uuid;
  v_phone text;
begin
  select site_id, phone into v_site, v_phone from public.residents where id = p_resident_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if v_phone is null then
    raise exception 'Telefonu olmayan sakine hesap açılamaz' using errcode = '22023';
  end if;
  return v_phone;
end;
$$;
revoke execute on function public.resident_account_phone(uuid) from public, anon;
grant execute on function public.resident_account_phone(uuid) to authenticated;

-- Telefonun giriş hesabı (sadece sunucu): varsa kimliği
create function public.resident_auth_user(p_phone text)
returns uuid
language sql stable security definer set search_path = ''
as $$ select id from auth.users where email = public.resident_login_email(p_phone) $$;
revoke execute on function public.resident_auth_user(text) from public, anon, authenticated;
grant execute on function public.resident_auth_user(text) to service_role;

-- Rehber kaydını giriş hesabına bağla (yönetici). Sadece o telefonun sakin hesabı bağlanabilir (yönetici/başka hesap değil).
create function public.link_resident_account(p_resident_id uuid, p_user_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_phone text := public.resident_account_phone(p_resident_id);
begin
  if not exists (select 1 from auth.users where id = p_user_id and email = public.resident_login_email(v_phone)) then
    raise exception 'Hesap bu sakinin telefonuna ait değil' using errcode = '42501';
  end if;
  update public.residents set user_id = p_user_id where id = p_resident_id;
end;
$$;
revoke execute on function public.link_resident_account(uuid, uuid) from public, anon;
grant execute on function public.link_resident_account(uuid, uuid) to authenticated;

-- Hesabı kapat (yönetici): sakin bu sitenin bilgilerini artık göremez. Döner: hesap başka sitede hâlâ kullanılıyor mu?
create function public.unlink_resident_account(p_resident_id uuid)
returns boolean
language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
  v_user uuid;
begin
  select site_id, user_id into v_site, v_user from public.residents where id = p_resident_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  update public.residents set user_id = null where id = p_resident_id;
  return exists (select 1 from public.residents where user_id = v_user);
end;
$$;
revoke execute on function public.unlink_resident_account(uuid) from public, anon;
grant execute on function public.unlink_resident_account(uuid) to authenticated;

-- ---------------------------------------------------------------
-- Uygulama içi mesajlar (sakinin gelen kutusu)
-- ---------------------------------------------------------------
create table public.resident_messages (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  resident_id uuid not null references public.residents (id) on delete cascade,
  kind text not null check (kind in ('odeme', 'hatirlatma', 'kargo', 'ariza', 'duyuru')),
  title text not null check (length(title) between 2 and 120),
  body text not null check (length(body) between 2 and 2000),
  url text check (url is null or url like '/sakin%'),
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  read_at timestamptz,
  pushed_at timestamptz
);
create index on public.resident_messages (resident_id, created_at desc);
create index on public.resident_messages (site_id, created_at desc) where pushed_at is null;

alter table public.resident_messages enable row level security;
revoke all on public.resident_messages from public, anon, authenticated;
grant select on public.resident_messages to authenticated;
create policy "sakin mesajı görme (yönetim)" on public.resident_messages for select to authenticated
  using ((select public.has_site_role(site_id, '{yonetici}')) or (select public.is_site_viewer(site_id)));

-- Birimin, mesajı alacak hesaplı sakinleri. p_on: kiracı ancak bu tarihte veya sonrasında oturuyorsa (null = hepsi)
create function public.unit_app_residents(p_unit_id uuid, p_on date default null)
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select distinct r.id
  from public.unit_residents ur join public.residents r on r.id = ur.resident_id
  where ur.unit_id = p_unit_id and ur.ended_on is null and r.user_id is not null
    and (p_on is null or ur.relation = 'malik' or ur.start_unknown or p_on >= ur.started_on)
$$;
revoke execute on function public.unit_app_residents(uuid, date) from public, anon, authenticated;

create function public.unit_label(p_unit_id uuid)
returns text
language sql stable security definer set search_path = ''
as $$ select b.name || '-' || u.no from public.units u join public.blocks b on b.id = u.block_id where u.id = p_unit_id $$;
revoke execute on function public.unit_label(uuid) from public, anon, authenticated;

-- Ödeme kaydedilince: "Ödemeniz alındı" (makbuz numarasıyla)
create function public.message_on_payment()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.resident_messages (site_id, resident_id, kind, title, body, url)
  select new.site_id, r, 'odeme', 'Ödemeniz alındı',
         public.unit_label(new.unit_id) || ' için ' || to_char(new.paid_on, 'DD.MM.YYYY') || ' tarihli ' || public.tr_money(new.amount)
         || ' ödemeniz kaydedildi.' || coalesce(' Makbuz no: ' || new.receipt_year || '-' || lpad(new.receipt_no::text, 4, '0') || '.', ''),
         '/sakin/makbuz/' || new.id
  from public.unit_app_residents(new.unit_id, new.paid_on) r;
  return null;
end;
$$;
revoke execute on function public.message_on_payment() from public, anon, authenticated;
create trigger message_on_payment after insert on public.payments for each row when (new.status = 'aktif') execute function public.message_on_payment();

-- Kargo gelince
create function public.message_on_package()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.resident_messages (site_id, resident_id, kind, title, body, url)
  select new.site_id, r, 'kargo', 'Kargonuz geldi',
         public.unit_label(new.unit_id) || ' adına kargonuz danışmaya ulaştı. Danışmadan teslim alabilirsiniz.', '/sakin'
  from public.unit_app_residents(new.unit_id) r;
  -- Uygulamadan haber verildiyse kargo "haber verildi" sayılır
  if found then
    update public.packages set notified_at = now() where id = new.id and notified_at is null;
  end if;
  return null;
end;
$$;
revoke execute on function public.message_on_package() from public, anon, authenticated;
create trigger message_on_package after insert on public.packages for each row execute function public.message_on_package();

-- Arıza: kayda alındı / giderildi (sadece bir birime bağlı arızalar)
create function public.message_on_ticket()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.unit_id is null then
    return null;
  end if;
  if tg_op = 'INSERT' then
    insert into public.resident_messages (site_id, resident_id, kind, title, body, url)
    select new.site_id, r, 'ariza', 'Arıza kaydı alındı',
           public.unit_label(new.unit_id) || ' için bildirilen arıza kayda alındı: "' || left(new.description, 200) || '"', '/sakin'
    from public.unit_app_residents(new.unit_id) r;
  elsif new.status = 'tamamlandi' and old.status <> 'tamamlandi' then
    insert into public.resident_messages (site_id, resident_id, kind, title, body, url)
    select new.site_id, r, 'ariza', 'Arıza giderildi',
           public.unit_label(new.unit_id) || ' için bildirilen arıza giderildi: "' || left(new.description, 200) || '". Sorun devam ederse danışmaya bildiriniz.', '/sakin'
    from public.unit_app_residents(new.unit_id) r;
  end if;
  return null;
end;
$$;
revoke execute on function public.message_on_ticket() from public, anon, authenticated;
create trigger message_on_ticket after insert or update of status on public.tickets for each row execute function public.message_on_ticket();

-- Duyuru arşive yazılınca sitenin bütün hesaplı sakinlerine
create function public.message_on_announcement()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.resident_messages (site_id, resident_id, kind, title, body, url)
  select distinct new.site_id, r.id, 'duyuru', left(new.title, 120), left(new.body, 2000), '/sakin'
  from public.residents r
  where r.site_id = new.site_id and r.user_id is not null
    and exists (select 1 from public.unit_residents ur where ur.resident_id = r.id and ur.ended_on is null);
  return null;
end;
$$;
revoke execute on function public.message_on_announcement() from public, anon, authenticated;
create trigger message_on_announcement after insert on public.announcements for each row execute function public.message_on_announcement();

-- Uygulamadan borç hatırlatması (yönetici): hatırlatma kaydı + mesaj. Metni uygulama hazırlar.
create function public.send_app_reminder(p_unit_id uuid, p_resident_id uuid, p_amount numeric, p_body text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
begin
  select site_id into v_site from public.units where id = p_unit_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if not exists (select 1 from public.unit_app_residents(p_unit_id) r where r = p_resident_id) then
    raise exception 'Bu sakinin uygulama hesabı yok' using errcode = '22023';
  end if;
  if p_amount is null or p_amount <= 0 or coalesce(length(trim(p_body)), 0) not between 10 and 2000 then
    raise exception 'Hatırlatma hatalı' using errcode = '22023';
  end if;
  insert into public.reminders (site_id, unit_id, resident_id, amount) values (v_site, p_unit_id, p_resident_id, round(p_amount, 2));
  insert into public.resident_messages (site_id, resident_id, kind, title, body, url)
  values (v_site, p_resident_id, 'hatirlatma', 'Ödenmemiş borç hatırlatması', trim(p_body), '/sakin');
end;
$$;
revoke execute on function public.send_app_reminder(uuid, uuid, numeric, text) from public, anon;
grant execute on function public.send_app_reminder(uuid, uuid, numeric, text) to authenticated;

-- Sakin: mesajlarını okundu say
create function public.mark_my_messages_read()
returns void
language sql security definer set search_path = ''
as $$
  update public.resident_messages set read_at = now()
  where read_at is null and resident_id in (select id from public.residents where user_id = auth.uid())
$$;
revoke execute on function public.mark_my_messages_read() from public, anon;
grant execute on function public.mark_my_messages_read() to authenticated;

-- Sakin: ilk girişte KVKK aydınlatmasını gördü (rehber kaydına "uygulama" olarak yazılır)
create function public.mark_me_informed()
returns void
language sql security definer set search_path = ''
as $$
  update public.residents set informed_at = now(), informed_via = 'uygulama'
  where user_id = auth.uid() and informed_at is null
$$;
revoke execute on function public.mark_me_informed() from public, anon;
grant execute on function public.mark_me_informed() to authenticated;
