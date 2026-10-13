-- Telefon uygulaması: giriş ve davet (adım 3, kullanıcı kararı 06.10.2026)
-- • Herkes telefon + şifreyle girer (SMS yok). Giriş hesabı telefondan türetilen iç adresle: tel-905321234567@sitedesk.invalid
-- • Site → Blok → Daire/Villa. Bir dairede birden çok kişi, bir kişi birden çok dairede (unit_residents). Taşınan kişinin
--   erişimi tek dokunuşla kapanır (ended_on); kayıt silinmez.
-- • Davet: yönetici sakin ve danışma, danışma sakin, sistem yöneticisi yönetici davet eder. Davet 8 haneli kod + uzun bağlantı
--   anahtarıyla, 7 gün geçerli, tek kullanımlık. Kabul, kişinin kendi oturumuyla veritabanında yapılır (telefon eşleşmeli).
-- • İşlem geçmişi (audit_log): blok, daire, sakin, daire bağlantısı, üyelik ve davet değişiklikleri tetikleyiciyle yazılır.
-- Eski web'in "sakin hesabı" fonksiyonları kaldırılır (yeni giriş biçimiyle çakışıyor).

set local lock_timeout = '15s';
set local statement_timeout = '60s';

-- ---------- Eski sakin hesabı fonksiyonları ----------
drop function if exists public.resident_account_phone(uuid), public.link_resident_account(uuid, uuid),
  public.unlink_resident_account(uuid), public.resident_auth_user(text), public.resident_login_email(text), public.my_resident_summary();
drop index if exists public.residents_site_phone; -- aynısı residents_site_phone_unique olarak duruyor

-- Telefondan giriş adresi (uygulamadaki lib/login.ts ile aynı)
create function public.login_email(p_phone text)
returns text language sql immutable set search_path = ''
as $$ select 'tel-' || p_phone || '@sitedesk.invalid' $$;

-- Giriş yapan kişinin telefonu (iç adresten); e-postayla giren için boş
create function public.my_phone()
returns text language sql stable security definer set search_path = ''
as $$
  select substring(email from '^tel-([0-9]+)@sitedesk\.invalid$') from auth.users where id = (select auth.uid())
$$;

-- ---------- Site ayarları ----------
alter table public.sites
  add column is_demo boolean not null default false,
  add column video_keep_months smallint not null default 6 check (video_keep_months between 1 and 60);

-- ---------- Blok ve daire/villa ----------
create table public.blocks (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  name text not null check (length(trim(name)) between 1 and 30),
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  unique (site_id, name),
  unique (id, site_id)
);

create table public.units (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  block_id uuid not null,
  no text not null check (length(trim(no)) between 1 and 20),
  type text not null default 'daire' check (type in ('daire', 'villa')),
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  foreign key (block_id, site_id) references public.blocks (id, site_id) on delete restrict,
  unique (block_id, no),
  unique (id, site_id)
);
create index on public.units (site_id);

-- Kişi ↔ daire (malik / kiracı / diğer hane üyesi)
create table public.unit_residents (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null,
  unit_id uuid not null,
  resident_id uuid not null,
  relation text not null default 'malik' check (relation in ('malik', 'kiraci', 'hane')),
  started_on date not null default current_date,
  ended_on date check (ended_on is null or ended_on >= started_on),
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  foreign key (unit_id, site_id) references public.units (id, site_id) on delete restrict,
  foreign key (resident_id, site_id) references public.residents (id, site_id) on delete restrict
);
create unique index unit_residents_active on public.unit_residents (unit_id, resident_id) where ended_on is null;
create index on public.unit_residents (site_id);
create index on public.unit_residents (resident_id);

-- ---------- Davetler ----------
create table public.invites (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  role text not null check (role in ('sakin', 'danisma', 'yonetici')),
  unit_id uuid,
  relation text check (relation in ('malik', 'kiraci', 'hane')),
  full_name text not null check (length(trim(full_name)) between 3 and 100),
  phone text not null check (phone ~ '^90[0-9]{10}$'),
  code text not null check (code ~ '^[A-Z2-9]{8}$'),
  token text not null check (length(token) >= 32),
  expires_at timestamptz not null default now() + interval '7 days',
  used_at timestamptz,
  used_by uuid references auth.users (id) on delete set null,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  foreign key (unit_id, site_id) references public.units (id, site_id) on delete restrict,
  check ((role = 'sakin') = (unit_id is not null and relation is not null))
);
create unique index invites_code on public.invites (code);
create unique index invites_token on public.invites (token);
create index on public.invites (site_id, created_at desc);

-- ---------- İşlem geçmişi ----------
create table public.audit_log (
  id bigint generated always as identity primary key,
  site_id uuid not null,
  at timestamptz not null default now(),
  actor_id uuid,
  actor_name text,
  entity text not null,
  action text not null check (action in ('ekle', 'degistir', 'sil')),
  record_id uuid,
  old_data jsonb,
  new_data jsonb
);
create index on public.audit_log (site_id, at desc);

create function public.write_audit()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_row jsonb := to_jsonb(coalesce(new, old));
  v_actor uuid := auth.uid();
begin
  insert into public.audit_log (site_id, actor_id, actor_name, entity, action, record_id, old_data, new_data)
  values (
    (v_row ->> 'site_id')::uuid, v_actor,
    coalesce((select full_name from public.profiles where user_id = v_actor), 'Sistem'),
    tg_table_name,
    case tg_op when 'INSERT' then 'ekle' when 'UPDATE' then 'degistir' else 'sil' end,
    (v_row ->> 'id')::uuid,
    case when tg_op <> 'INSERT' then to_jsonb(old) end,
    case when tg_op <> 'DELETE' then to_jsonb(new) end
  );
  return coalesce(new, old);
end;
$$;
create trigger audit after insert or update or delete on public.blocks for each row execute function public.write_audit();
create trigger audit after insert or update or delete on public.units for each row execute function public.write_audit();
create trigger audit after insert or update or delete on public.residents for each row execute function public.write_audit();
create trigger audit after insert or update or delete on public.unit_residents for each row execute function public.write_audit();
create trigger audit after insert or update or delete on public.memberships for each row execute function public.write_audit();
create trigger audit after insert or update or delete on public.invites for each row execute function public.write_audit();

-- ---------- Davet fonksiyonları ----------

-- Davet oluştur: sakini yönetici veya danışma; danışmayı yönetici; yöneticiyi sistem yöneticisi davet eder
create function public.create_invite(p_site_id uuid, p_role text, p_full_name text, p_phone text, p_unit_id uuid default null, p_relation text default null)
returns table (code text, token text, expires_at timestamptz)
language plpgsql security definer set search_path = ''
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text;
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_expires timestamptz := now() + interval '7 days';
begin
  if not (case p_role
            when 'sakin' then public.has_site_role(p_site_id, '{yonetici,danisma}')
            when 'danisma' then public.has_site_role(p_site_id, '{yonetici}')
            when 'yonetici' then public.is_platform_admin()
            else false end) then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if p_role = 'sakin' and not exists (select 1 from public.units where id = p_unit_id and site_id = p_site_id) then
    raise exception 'Daire bu sitede değil' using errcode = '22023';
  end if;
  -- Aynı kişiye aynı yer için açık davet varsa iptal edilir (yenisi geçerli olur)
  update public.invites i set cancelled_at = now()
  where i.site_id = p_site_id and i.phone = p_phone and i.role = p_role and i.unit_id is not distinct from p_unit_id
    and i.used_at is null and i.cancelled_at is null;
  loop
    v_code := (select string_agg(substr(v_alphabet, 1 + (get_byte(extensions.gen_random_bytes(1), 0) % length(v_alphabet)), 1), '')
               from generate_series(1, 8));
    exit when not exists (select 1 from public.invites i where i.code = v_code);
  end loop;
  insert into public.invites (site_id, role, unit_id, relation, full_name, phone, code, token, expires_at)
  values (p_site_id, p_role, case when p_role = 'sakin' then p_unit_id end, case when p_role = 'sakin' then coalesce(p_relation, 'malik') end,
          trim(p_full_name), p_phone, v_code, v_token, v_expires);
  return query select v_code, v_token, v_expires;
end;
$$;

create function public.cancel_invite(p_invite_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_inv public.invites;
begin
  select * into v_inv from public.invites where id = p_invite_id;
  if not found or not (case v_inv.role
            when 'sakin' then public.has_site_role(v_inv.site_id, '{yonetici,danisma}')
            when 'danisma' then public.has_site_role(v_inv.site_id, '{yonetici}')
            else public.is_platform_admin() end) then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  update public.invites set cancelled_at = now() where id = p_invite_id and used_at is null and cancelled_at is null;
end;
$$;

-- Davet önizleme (girişsiz de çağrılır): kod veya bağlantı anahtarıyla. Telefonun sadece son 4 hanesi görünür.
create function public.invite_preview(p_key text)
returns jsonb language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'valid', i.used_at is null and i.cancelled_at is null and i.expires_at > now(),
    'status', case when i.used_at is not null then 'kullanildi' when i.cancelled_at is not null then 'iptal'
                   when i.expires_at <= now() then 'suresi-doldu' else 'gecerli' end,
    'code', i.code,
    'role', i.role,
    'full_name', i.full_name,
    'phone_last4', right(i.phone, 4),
    'site_name', s.name,
    'unit_label', (select b.name || '-' || u.no from public.units u join public.blocks b on b.id = u.block_id where u.id = i.unit_id),
    'has_account', exists (select 1 from auth.users au where au.email = public.login_email(i.phone))
  )
  from public.invites i join public.sites s on s.id = i.site_id
  where i.code = upper(trim(p_key)) or i.token = trim(p_key)
$$;

-- Daveti kabul et: kişinin kendi oturumuyla; giriş telefonu davetteki telefonla aynı olmalı
create function public.accept_invite(p_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_inv public.invites;
  v_uid uuid := auth.uid();
  v_res uuid;
begin
  select * into v_inv from public.invites where code = upper(trim(p_key)) or token = trim(p_key) for update;
  if not found or v_inv.used_at is not null or v_inv.cancelled_at is not null or v_inv.expires_at <= now() then
    raise exception 'Davet geçersiz veya süresi dolmuş' using errcode = '22023';
  end if;
  if v_uid is null or public.my_phone() is distinct from v_inv.phone then
    raise exception 'Bu davet başka bir telefon numarası için' using errcode = '42501';
  end if;

  insert into public.profiles (user_id, full_name, phone) values (v_uid, v_inv.full_name, v_inv.phone)
  on conflict (user_id) do update set full_name = coalesce(nullif(public.profiles.full_name, ''), excluded.full_name),
                                      phone = coalesce(public.profiles.phone, excluded.phone);

  if v_inv.role = 'sakin' then
    -- Aynı sitede aynı telefon bir kişidir
    select id into v_res from public.residents where site_id = v_inv.site_id and phone = v_inv.phone;
    if v_res is null then
      insert into public.residents (site_id, full_name, phone, user_id) values (v_inv.site_id, v_inv.full_name, v_inv.phone, v_uid) returning id into v_res;
    else
      update public.residents set user_id = v_uid where id = v_res;
    end if;
    insert into public.unit_residents (site_id, unit_id, resident_id, relation)
    values (v_inv.site_id, v_inv.unit_id, v_res, v_inv.relation)
    on conflict (unit_id, resident_id) where ended_on is null do nothing;
  else
    insert into public.memberships (user_id, site_id, role) values (v_uid, v_inv.site_id, v_inv.role::public.site_role)
    on conflict (user_id, site_id, role) where ended_on is null do nothing;
  end if;

  update public.invites set used_at = now(), used_by = v_uid where id = v_inv.id;
  return jsonb_build_object('role', v_inv.role, 'site_id', v_inv.site_id);
end;
$$;

-- Taşınan / ayrılan kişinin daire erişimini kapatır (kayıt silinmez)
create function public.end_residency(p_unit_resident_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_site uuid;
begin
  select site_id into v_site from public.unit_residents where id = p_unit_resident_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  update public.unit_residents set ended_on = greatest(current_date, started_on) where id = p_unit_resident_id and ended_on is null;
end;
$$;

-- Giriş yapan kişinin rolleri: uygulama açılınca hangi ekranın görüneceğine karar verir
create function public.my_context()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'platform_admin', public.is_platform_admin(),
    'full_name', (select full_name from public.profiles where user_id = (select auth.uid())),
    'staff', coalesce((select jsonb_agg(jsonb_build_object('role', m.role, 'site_id', m.site_id, 'site_name', s.name) order by s.name)
                       from public.memberships m join public.sites s on s.id = m.site_id
                       where m.user_id = (select auth.uid()) and m.ended_on is null), '[]'::jsonb),
    'units', coalesce((select jsonb_agg(jsonb_build_object('unit_id', u.id, 'site_id', s.id, 'site_name', s.name,
                                                           'label', b.name || '-' || u.no, 'type', u.type, 'relation', ur.relation)
                                        order by s.name, b.name, u.no)
                       from public.residents r
                       join public.unit_residents ur on ur.resident_id = r.id and ur.ended_on is null
                       join public.units u on u.id = ur.unit_id join public.blocks b on b.id = u.block_id
                       join public.sites s on s.id = r.site_id
                       where r.user_id = (select auth.uid())), '[]'::jsonb)
  )
$$;

-- ---------- Yetkiler ----------
revoke all on public.blocks, public.units, public.unit_residents, public.invites, public.audit_log from anon, authenticated;
grant select, insert, update, delete on public.blocks, public.units to authenticated;
grant select on public.unit_residents, public.invites, public.audit_log to authenticated;
revoke execute on function public.create_invite(uuid, text, text, text, uuid, text), public.cancel_invite(uuid), public.accept_invite(text),
  public.end_residency(uuid), public.my_context(), public.my_phone(), public.write_audit() from public, anon;
grant execute on function public.create_invite(uuid, text, text, text, uuid, text), public.cancel_invite(uuid), public.accept_invite(text),
  public.end_residency(uuid), public.my_context(), public.my_phone() to authenticated;
revoke execute on function public.invite_preview(text) from public;
grant execute on function public.invite_preview(text) to anon, authenticated;

alter table public.blocks enable row level security;
alter table public.units enable row level security;
alter table public.unit_residents enable row level security;
alter table public.invites enable row level security;
alter table public.audit_log enable row level security;

-- Blok ve daire: sitenin yönetici ve danışması görür; yönetici düzenler; sakin kendi dairesini görür
create policy "blok görme" on public.blocks for select to authenticated
  using (site_id in (select public.my_site_ids('{yonetici,danisma}'))
         or exists (select 1 from public.units u join public.unit_residents ur on ur.unit_id = u.id and ur.ended_on is null
                    join public.residents r on r.id = ur.resident_id where u.block_id = blocks.id and r.user_id = (select auth.uid())));
create policy "blok yönetimi" on public.blocks for all to authenticated
  using (site_id in (select public.my_site_ids('{yonetici}'))) with check (site_id in (select public.my_site_ids('{yonetici}')));
create policy "daire görme" on public.units for select to authenticated
  using (site_id in (select public.my_site_ids('{yonetici,danisma}'))
         or exists (select 1 from public.unit_residents ur join public.residents r on r.id = ur.resident_id
                    where ur.unit_id = units.id and ur.ended_on is null and r.user_id = (select auth.uid())));
create policy "daire yönetimi" on public.units for all to authenticated
  using (site_id in (select public.my_site_ids('{yonetici}'))) with check (site_id in (select public.my_site_ids('{yonetici}')));

-- Daire bağlantısı: sitenin yönetici ve danışması görür; kişi kendi bağlantılarını görür. Yazma sadece fonksiyonlarla.
create policy "bağlantı görme" on public.unit_residents for select to authenticated
  using (site_id in (select public.my_site_ids('{yonetici,danisma}'))
         or resident_id in (select r.id from public.residents r where r.user_id = (select auth.uid())));

-- Davet: sitenin yönetici ve danışması görür (yazma sadece fonksiyonlarla)
create policy "davet görme" on public.invites for select to authenticated
  using (site_id in (select public.my_site_ids('{yonetici,danisma}')));

-- İşlem geçmişi: sadece sitenin yöneticisi (ve sistem yöneticisi)
create policy "geçmiş görme" on public.audit_log for select to authenticated using (site_id in (select public.my_site_ids('{yonetici}')));

-- Sakin rehberi: yönetici de düzenler (ad, telefon); sistem yöneticisi her şeyi
drop policy "sakin düzenleme" on public.residents;
create policy "sakin düzenleme" on public.residents for update to authenticated
  using (site_id in (select public.my_site_ids('{yonetici}'))) with check (site_id in (select public.my_site_ids('{yonetici}')));

-- Üyelik: sitenin yöneticisi kendi sitesinin üyeliklerini görür ve danışmanın erişimini kapatır
drop policy "üyelik görme" on public.memberships;
create policy "üyelik görme" on public.memberships for select to authenticated
  using (user_id = (select auth.uid()) or site_id in (select public.my_site_ids('{yonetici}')));
drop policy "üyelik düzenleme" on public.memberships;
create policy "üyelik düzenleme" on public.memberships for update to authenticated
  using ((select public.is_platform_admin()) or (role = 'danisma' and site_id in (select public.my_site_ids('{yonetici}'))))
  with check ((select public.is_platform_admin()) or (role = 'danisma' and site_id in (select public.my_site_ids('{yonetici}'))));

-- Profil: sitenin yöneticisi kendi sitesindeki kişilerin adını ve telefonunu görür
drop policy "profil görme" on public.profiles;
create policy "profil görme" on public.profiles for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_platform_admin())
         or exists (select 1 from public.memberships m where m.user_id = profiles.user_id and m.site_id in (select public.my_site_ids('{yonetici}'))));
