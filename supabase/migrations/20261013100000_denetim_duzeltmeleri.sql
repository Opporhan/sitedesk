-- Bağımsız denetim düzeltmeleri (kullanıcı onayı 12-13.10.2026):
-- 1) İşlem geçmişi: davet/şifre kodları yazılmaz (eskileri silinir), kargo ve ziyaretçi hiç yazılmaz (eskileri silinir),
--    uygulama geçmişi okuyamaz (zaten kullanmıyordu), 1 yıldan eski geçmiş her gece silinir.
-- 2) Yeni gelen sakin, taşınmadan önce açılmış arıza/talep kayıtlarını (fotoğraf, açıklama) görmez ve onların bildirimini almaz.
-- 3) Şifre yenilenince kişinin bütün oturumları kapanır, kişiye bildirim gider ve eski telefonların bildirim kaydı silinir
--    (sunucu çağırır: password_changed). Açık erişim anahtarı en geç 1 saatte düşer.
-- 4) Sağlık raporu yeni gece işini de izler; taşınma başlangıcı/bitişi Türkiye tarihiyle yazılır.
-- 5) Hesap açma: toplam saatlik sınır kaldırıldı (herkesi kilitlemek için kullanılabiliyordu); adres başına sınır kalır.
-- 6) Küçük güvenlik: dosya sayma fonksiyonu sadece kişinin yetkili olduğu klasörü sayar;
--    başka bir sitede yönetici olan kişinin şifre kodunu sadece sistem yöneticisi açar; kapalı site üyelere görünmez;
--    yönetici daveti "gönderildi" işaretlenebilir.
-- 7) Temizlik: ödeme tarihi (paid_until; uygulama ücretsiz), profiles.email ve 'hane' ilişki değeri kaldırıldı.
set local lock_timeout = '15s';
set local statement_timeout = '60s';

-- ---------- 1) İşlem geçmişi ----------
create or replace function public.write_audit()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_row jsonb := to_jsonb(coalesce(new, old));
  v_actor uuid := auth.uid();
  v_old jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  v_new jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
begin
  if tg_table_name = 'invites' then -- kod ve bağlantı anahtarı geçmişe yazılmaz (yazılırsa başkası şifre kodunu okuyabilirdi)
    v_old := v_old - 'code' - 'token';
    v_new := v_new - 'code' - 'token';
  end if;
  insert into public.audit_log (site_id, actor_id, actor_name, entity, action, record_id, old_data, new_data)
  values (
    (v_row ->> 'site_id')::uuid, v_actor,
    coalesce((select full_name from public.profiles where user_id = v_actor), 'Sistem'),
    tg_table_name,
    case tg_op when 'INSERT' then 'ekle' when 'UPDATE' then 'degistir' else 'sil' end,
    (v_row ->> 'id')::uuid, v_old, v_new
  );
  return coalesce(new, old);
end;
$$;

drop trigger audit on public.packages;
drop trigger audit on public.visitors;
delete from public.audit_log where entity in ('packages', 'visitors');
update public.audit_log set old_data = old_data - 'code' - 'token', new_data = new_data - 'code' - 'token' where entity = 'invites';

revoke all on public.audit_log from anon, authenticated;
drop policy "geçmiş görme" on public.audit_log;

create function public.purge_old_audit()
returns void language sql security definer set search_path = ''
as $$ delete from public.audit_log where at < now() - interval '1 year' $$;
revoke execute on function public.purge_old_audit() from public, anon, authenticated;
select cron.schedule('gecmis-temizlik', '45 1 * * *', 'select public.purge_old_audit()');

-- ---------- 2) Yeni sakin eski kayıtları görmez ----------
drop policy "kayıt görme" on public.tickets;
create policy "kayıt görme" on public.tickets for select to authenticated using (
  site_id in (select public.my_site_ids('{yonetici,danisma}'))
  or public.resident_can_see(unit_id, created_at, false)
);

create or replace function public.ticket_role(p_ticket_id uuid)
returns text language sql stable security definer set search_path = ''
as $$
  select case
    when public.has_site_role(t.site_id, '{yonetici}') then 'yonetici'
    when public.has_site_role(t.site_id, '{danisma}') then 'danisma'
    when public.resident_can_see(t.unit_id, t.created_at, false) then 'sakin'
  end
  from public.tickets t where t.id = p_ticket_id
$$;

create or replace function public.notify_ticket_event()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_t public.tickets;
  v_status text := case new.status when 'alindi' then 'Yeni' when 'inceleniyor' then 'İnceleniyor' when 'yapiliyor' then 'Yapılıyor' when 'tamamlandi' then 'Tamamlandı' else new.status end;
  v_residents uuid[];
begin
  select * into v_t from public.tickets where id = new.ticket_id;
  -- Sadece kayıt açıldığında dairede oturanlar (sonradan taşınan, eski kaydın bildirimini almaz)
  select coalesce(array_agg(distinct r.user_id), '{}') into v_residents
  from public.unit_residents ur join public.residents r on r.id = ur.resident_id
  where ur.unit_id = v_t.unit_id and ur.ended_on is null and r.user_id is not null
    and v_t.created_at >= (ur.started_on::timestamp at time zone 'Europe/Istanbul');
  if new.author_role in ('yonetici', 'danisma') then
    if new.kind = 'durum' then
      perform public.notify_users(v_residents, v_t.title, 'Durum: ' || v_status || coalesce(' · ' || new.body, ''), '/kayit/' || v_t.id);
    elsif new.kind = 'not' then
      perform public.notify_users(v_residents, 'Yönetimden cevap · ' || v_t.title, new.body, '/kayit/' || v_t.id);
    end if;
  elsif new.kind = 'sonuc' and new.status = 'devam' then
    perform public.notify_users(public.site_manager_users(v_t.site_id), public.unit_label(v_t.unit_id) || ': Sorun devam ediyor',
      v_t.title || coalesce(' · ' || new.body, ''), '/kayit/' || v_t.id);
  end if;
  return new;
end;
$$;

-- ---------- 3) Şifre değişince oturumlar kapanır + bildirim (sadece sunucu) ----------
create function public.password_changed(p_user uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  delete from auth.sessions where user_id = p_user; -- yenileme anahtarları da silinir (cascade)
  -- Önce bildirim (eski telefonlar da görsün), sonra telefon kayıtları silinir: eski telefon bu hesabın bildirimlerini artık almaz
  perform public.notify_users(array[p_user], 'Şifreniz yenilendi',
    'Hesabınızın şifresi yenilendi ve diğer telefonlardaki oturumlar kapatıldı. Bunu siz yapmadıysanız hemen yönetiminize haber verin.', '/');
  delete from public.push_tokens where user_id = p_user;
end;
$$;
revoke execute on function public.password_changed(uuid) from public, anon, authenticated;
grant execute on function public.password_changed(uuid) to service_role;

-- ---------- 4) Sağlık raporu ve Türkiye tarihi ----------
create or replace function public.health_report()
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_removed int;
begin
  -- Expo "DeviceNotRegistered" dediği telefonlar (uygulama silinmiş) kayıttan çıkar
  begin
    with bad as (
      select distinct d -> 'details' ->> 'expoPushToken' as token
      from net._http_response r, jsonb_array_elements(r.content::jsonb -> 'data') d
      where r.created > now() - interval '1 day' and r.status_code = 200 and r.content like '{"data":[%'
        and d -> 'details' ->> 'error' = 'DeviceNotRegistered'
    ), del as (delete from public.push_tokens t using bad where t.token = bad.token returning 1)
    select count(*) into v_removed from del;
  exception when others then
    v_removed := -1; -- okunamayan cevap; rapor yine döner
  end;

  return jsonb_build_object(
    'cron_failed', coalesce((select jsonb_agg(distinct j.jobname) from cron.job_run_details d join cron.job j on j.jobid = d.jobid
                             where d.status = 'failed' and d.start_time > now() - interval '2 days'), '[]'::jsonb),
    'cron_missing', coalesce((select jsonb_agg(x) from unnest(array['ziyaretci-temizlik', 'gecmis-temizlik']) x
                              where not exists (select 1 from cron.job j where j.jobname = x and j.active)), '[]'::jsonb),
    'push_failed', (select count(*) from net._http_response r where r.created > now() - interval '1 day'
                    and (r.status_code is null or r.status_code >= 400)),
    'push_tokens_removed', v_removed
  );
end;
$$;

-- Veritabanı UTC çalışır; gece 00:00–03:00 arası taşınan kişinin başlangıcı bir gün önceye yazılmasın
alter table public.unit_residents alter column started_on set default ((now() at time zone 'Europe/Istanbul')::date);
create or replace function public.end_residency(p_unit_resident_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_site uuid;
begin
  select site_id into v_site from public.unit_residents where id = p_unit_resident_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  update public.unit_residents set ended_on = greatest((now() at time zone 'Europe/Istanbul')::date, started_on)
  where id = p_unit_resident_id and ended_on is null;
end;
$$;

-- ---------- 5) Hesap açma sınırı: sadece adres başına ----------
create or replace function public.allow_signup(p_ip_hash text)
returns boolean language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.signup_attempts where created_at < now() - interval '1 day';
  if (select count(*) from public.signup_attempts where ip_hash = p_ip_hash and created_at > now() - interval '1 hour') >= 20 then
    return false;
  end if;
  insert into public.signup_attempts (ip_hash) values (left(p_ip_hash, 128));
  return true;
end;
$$;

-- ---------- 6) Küçük güvenlik ----------
-- Dosya sayma: sadece kişinin yetkili olduğu klasör (yoksa sayı vermez); depo kurallarının içinden çağrılır
create or replace function public.storage_folder_count(p_bucket text, p_prefix text)
returns integer language sql stable security definer set search_path = ''
as $$
  select case
    when (p_bucket in ('profil', 'listeler') and p_prefix = (select auth.uid())::text || '/')
      or (p_bucket = 'kayitlar' and public.ticket_role(public.storage_ticket_id(p_prefix)) is not null)
    then (select count(*)::int from storage.objects where bucket_id = p_bucket and name like p_prefix || '%')
  end
$$;

create or replace function public.create_password_reset(p_site_id uuid, p_phone text)
returns table(code text, token text, expires_at timestamp with time zone, full_name text)
language plpgsql security definer set search_path = ''
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_user uuid;
  v_name text;
  v_role text;
  v_code text;
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_expires timestamptz := now() + interval '24 hours';
begin
  select u.id into v_user from auth.users u where u.email = public.login_email(p_phone);
  if v_user is null then raise exception 'Bu numarayla uygulama hesabı yok; davet gönderin' using errcode = '22023'; end if;
  if exists (select 1 from public.platform_admins where user_id = v_user) then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;

  -- Kişinin bu sitedeki rolü
  if exists (select 1 from public.memberships where user_id = v_user and site_id = p_site_id and role = 'yonetici' and ended_on is null) then v_role := 'yonetici';
  elsif exists (select 1 from public.memberships where user_id = v_user and site_id = p_site_id and role = 'danisma' and ended_on is null) then v_role := 'danisma';
  elsif exists (select 1 from public.residents r join public.unit_residents ur on ur.resident_id = r.id and ur.ended_on is null
                where r.user_id = v_user and r.site_id = p_site_id) then v_role := 'sakin';
  end if;
  if v_role is null then raise exception 'Bu kişi bu sitede kayıtlı değil' using errcode = '22023'; end if;

  if not public.is_platform_admin() then
    if v_role = 'yonetici' or not public.has_site_role(p_site_id, '{yonetici}') then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
    -- Herhangi bir sitede yönetici olan kişinin şifresini sadece sistem yöneticisi yeniler
    if exists (select 1 from public.memberships where user_id = v_user and role = 'yonetici' and ended_on is null) then
      raise exception 'Bu kişi başka bir sitede yönetici; şifresini sistem yöneticisi yenileyebilir' using errcode = '42501';
    end if;
    -- Kişinin bulunduğu her sitede yönetici olmalı (başka sitedeki hesabı ele geçiremesin)
    if exists (select 1 from public.user_site_ids(v_user) s where not public.has_site_role(s, '{yonetici}')) then
      raise exception 'Bu kişi başka sitelerde de kayıtlı; şifresini sistem yöneticisi yenileyebilir' using errcode = '42501';
    end if;
  end if;

  select coalesce(nullif(p.full_name, ''), 'Kullanıcı') into v_name from public.profiles p where p.user_id = v_user;
  update public.invites i set cancelled_at = now() where i.phone = p_phone and i.role = 'sifre' and i.used_at is null and i.cancelled_at is null;
  loop
    v_code := (select string_agg(substr(v_alphabet, 1 + (get_byte(extensions.gen_random_bytes(1), 0) % length(v_alphabet)), 1), '')
               from generate_series(1, 8));
    exit when not exists (select 1 from public.invites i where i.code = v_code);
  end loop;
  insert into public.invites (site_id, role, full_name, phone, code, token, expires_at)
  values (p_site_id, 'sifre', coalesce(v_name, 'Kullanıcı'), p_phone, v_code, v_token, v_expires);
  return query select v_code, v_token, v_expires, coalesce(v_name, 'Kullanıcı');
end;
$$;

-- Kapalı site üyelerine görünmez (site kodu dahil); sistem yöneticisi hepsini görür
drop policy "site görme" on public.sites;
create policy "site görme" on public.sites for select to authenticated using (
  (select public.is_platform_admin())
  or (active and (public.is_site_member(id) or exists (
        select 1 from public.residents r join public.unit_residents ur on ur.resident_id = r.id and ur.ended_on is null
        where r.site_id = sites.id and r.user_id = (select auth.uid()))))
);

create or replace function public.mark_invite_sent(p_invite_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_site uuid;
begin
  select site_id into v_site from public.invites where id = p_invite_id and role in ('sakin', 'danisma', 'yonetici');
  if v_site is null or not public.has_site_role(v_site, '{yonetici}') then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  update public.invites set sent_at = coalesce(sent_at, now()) where id = p_invite_id;
end;
$$;

-- ---------- 7) Temizlik ----------
drop function public.platform_site_stats();
alter table public.sites drop column paid_until;
create function public.platform_site_stats()
returns table(site_id uuid, name text, active boolean, is_demo boolean, units bigint, residents_with_app bigint, staff bigint, open_tickets bigint, storage_bytes bigint)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_platform_admin() then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  return query
  select s.id, s.name, s.active, s.is_demo,
    (select count(*) from public.units u where u.site_id = s.id),
    (select count(distinct r.id) from public.residents r join public.unit_residents ur on ur.resident_id = r.id and ur.ended_on is null
       where r.site_id = s.id and r.user_id is not null),
    (select count(*) from public.memberships m where m.site_id = s.id and m.ended_on is null),
    (select count(*) from public.tickets t where t.site_id = s.id and t.status <> 'tamamlandi'),
    coalesce((select sum((o.metadata ->> 'size')::bigint) from storage.objects o
              where o.bucket_id = 'kayitlar' and split_part(o.name, '/', 1) = s.id::text), 0)::bigint
  from public.sites s
  order by s.is_demo, s.name;
end;
$$;
revoke execute on function public.platform_site_stats() from public, anon;
grant execute on function public.platform_site_stats() to authenticated;

drop trigger on_auth_user_email_changed on auth.users;
drop function public.sync_user_email();
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (user_id, full_name, phone)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''), new.raw_user_meta_data ->> 'phone');
  return new;
end;
$$;
alter table public.profiles drop column email;

alter table public.unit_residents drop constraint unit_residents_relation_check;
alter table public.unit_residents add constraint unit_residents_relation_check check (relation in ('malik', 'kiraci'));
alter table public.invites drop constraint invites_relation_check;
alter table public.invites add constraint invites_relation_check check (relation in ('malik', 'kiraci'));
