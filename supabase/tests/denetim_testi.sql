-- Bağımsız denetim düzeltmeleri testi (13.10.2026): işlem geçmişinde kod yok ve uygulama okuyamaz; yeni sakin eski kayıtları ve
-- dosyalarını görmez; sunucu fonksiyonları uygulamadan çağrılamaz; şifre değişince oturumlar ve telefon kayıtları silinir; dosya sayma
-- sadece yetkili klasörü sayar; başka sitede yönetici olanın şifre kodunu yönetici açamaz; kapalı site üyeye görünmez;
-- yönetici daveti "gönderildi" işaretlenir; hesap açmada toplam sınır yok. Sonunda HER ŞEY GERİ ALINIR.
-- Beklenen: "SONUÇ: 11 test geçti, 0 test kaldı. Her şey yolunda."
do $$
declare
  u_yon uuid := gen_random_uuid(); u_eski uuid := gen_random_uuid(); u_yeni uuid := gen_random_uuid(); u_b uuid := gen_random_uuid();
  u_sahip uuid := gen_random_uuid();
  s uuid; t_site uuid; blk uuid; d1 uuid; e1 uuid; r_eski uuid; r_yeni uuid; t_old uuid; t_new uuid; inv record; n int; j jsonb; ok boolean;
  gecti int := 0; kaldi int := 0; rapor text := '';
begin
  insert into auth.users (id, email) values (u_yon, public.login_email('905320005001')), (u_eski, public.login_email('905320005002')),
    (u_yeni, public.login_email('905320005003')), (u_b, public.login_email('905320005004')), (u_sahip, public.login_email('905320005005'));
  insert into public.sites (name, type) values ('DT Site', 'apartman') returning id into s;
  insert into public.sites (name, type) values ('DT Öbür', 'apartman') returning id into t_site;
  insert into public.memberships (user_id, site_id, role) values (u_yon, s, 'yonetici'), (u_yon, t_site, 'yonetici'), (u_b, s, 'yonetici');
  insert into public.blocks (site_id, name) values (s, 'A') returning id into blk;
  insert into public.units (site_id, block_id, no) values (s, blk, '1') returning id into d1;
  insert into public.blocks (site_id, name) values (t_site, 'B') returning id into blk;
  insert into public.units (site_id, block_id, no) values (t_site, blk, '1') returning id into e1;
  -- Eski sakin A-1'de oturuyordu, kayıt açtı, taşındı; yeni kiracı dün geldi
  insert into public.residents (site_id, full_name, phone, user_id) values (s, 'Eski Sakin', '905320005002', u_eski) returning id into r_eski;
  insert into public.unit_residents (site_id, unit_id, resident_id, relation, started_on) values (s, d1, r_eski, 'malik', current_date - 100);
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_eski, 'role', 'authenticated')::text, true);
  t_old := public.create_ticket(gen_random_uuid(), d1, 'ariza', 'daire', 'Eski arıza', 'Banyo', false);
  reset role;
  update public.tickets set created_at = now() - interval '10 days' where id = t_old;
  insert into storage.objects (bucket_id, name, metadata) values ('kayitlar', s || '/' || t_old || '/a.jpg', '{"mimetype": "image/jpeg", "size": 1000}');
  update public.unit_residents set ended_on = current_date - 1 where resident_id = r_eski;
  insert into public.residents (site_id, full_name, phone, user_id) values (s, 'Yeni Kiracı', '905320005003', u_yeni) returning id into r_yeni;
  insert into public.unit_residents (site_id, unit_id, resident_id, relation, started_on) values (s, d1, r_yeni, 'kiraci', current_date - 1);
  -- B: S'de yönetici, T'de sakin
  insert into public.residents (site_id, full_name, phone, user_id) values (t_site, 'B Kişi', '905320005004', u_b) returning id into r_eski;
  insert into public.unit_residents (site_id, unit_id, resident_id, relation) values (t_site, e1, r_eski, 'malik');

  -- 1: yeni kiracı eski kaydı ve dosyasını görmez, kendi kaydını görür
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_yeni, 'role', 'authenticated')::text, true);
  t_new := public.create_ticket(gen_random_uuid(), d1, 'ariza', 'daire', 'Yeni arıza', 'Mutfak', false);
  if (select count(*) from public.tickets where id = t_old) = 0 and (select count(*) from public.tickets where id = t_new) = 1
     and public.ticket_role(t_old) is null and (select count(*) from storage.objects where bucket_id = 'kayitlar' and name like s || '/' || t_old || '/%') = 0
  then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: yeni kiracı eski kaydı görüyor ya da kendi kaydını görmüyor'; end if;

  -- 2: yönetici şifre kodu açar; işlem geçmişinde kod/anahtar yok
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  select * into inv from public.create_invite(s, 'danisma', 'DT Danışma', '905320005009');
  reset role;
  if exists (select 1 from public.audit_log where entity = 'invites' and site_id = s)
     and not exists (select 1 from public.audit_log where entity = 'invites' and site_id = s and (new_data ? 'code' or new_data ? 'token'))
  then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: işlem geçmişinde davet kodu var (ya da kayıt yok)'; end if;

  -- 3: yönetici işlem geçmişini okuyamaz
  set local role authenticated;
  begin
    perform count(*) from public.audit_log;
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: yönetici işlem geçmişini okuyabiliyor';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;

  -- 4: sunucu fonksiyonları uygulamadan çağrılamaz
  n := 0;
  begin perform public.password_changed(u_b); exception when insufficient_privilege then n := n + 1; end;
  begin perform public.purge_old_audit(); exception when insufficient_privilege then n := n + 1; end;
  if n = 2 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: sunucu fonksiyonu uygulamadan çağrıldı (%s/2 engellendi)', n); end if;

  -- 5: şifre değişince (sunucu) oturumlar kapanır, bildirim gider, telefon kaydı silinir
  reset role;
  insert into auth.sessions (id, user_id) values (gen_random_uuid(), u_b);
  insert into public.push_tokens (token, user_id, platform) values ('ExponentPushToken[dt-b]', u_b, 'android');
  select count(*) into n from net.http_request_queue;
  perform public.password_changed(u_b);
  if not exists (select 1 from auth.sessions where user_id = u_b) and not exists (select 1 from public.push_tokens where user_id = u_b)
     and (select count(*) from net.http_request_queue) = n + 1
     and (select convert_from(q.body, 'utf8') from net.http_request_queue q order by id desc limit 1) like '%dt-b%Şifreniz yenilendi%'
  then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: şifre değişince oturum/telefon kaydı silinmedi ya da bildirim gitmedi'; end if;
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);

  -- 6: dosya sayma sadece yetkili klasörde sayı verir
  if public.storage_folder_count('profil', u_yon || '/') = 0 and public.storage_folder_count('profil', u_b || '/') is null
     and public.storage_folder_count('kayitlar', s || '/') is null and public.storage_folder_count('kayitlar', s || '/' || t_old || '/') = 1
  then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: dosya sayma başkasının klasörünü sayıyor'; end if;

  -- 7: başka sitede yönetici olan kişinin şifre kodunu (sakin olduğu site üzerinden) yönetici açamaz
  begin
    perform public.create_password_reset(t_site, '905320005004');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: yönetici, başka sitede yönetici olan kişinin şifre kodunu açtı';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;

  -- 8: yönetici daveti "gönderildi" işaretlenir
  select * into inv from public.create_invite(s, 'yonetici', 'DT Yönetici', '905320005008');
  perform public.mark_invite_sent((select id from public.invites where code = inv.code));
  if (select sent_at from public.invites where code = inv.code) is not null then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: yönetici daveti işaretlenmedi'; end if;
  reset role;

  -- 9: kapalı site üyeye (site kodu dahil) görünmez
  update public.sites set active = false where id = t_site;
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  if (select count(*) from public.sites where id = t_site) = 0 and (select count(*) from public.sites where id = s) = 1 then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: kapalı site üyeye görünüyor'; end if;
  reset role;

  -- 10: hesap açmada toplam sınır yok (farklı adreslerden 600 deneme geçer)
  n := 0;
  for i in 1 .. 600 loop
    if public.allow_signup('dt-adres-' || i) then n := n + 1; end if;
  end loop;
  if n = 600 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: toplam sınır hâlâ var (%s/600)', n); end if;

  -- 11: kargo ve ziyaretçi işlem geçmişine yazılmaz
  insert into public.memberships (user_id, site_id, role) values (u_sahip, s, 'danisma');
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_sahip, 'role', 'authenticated')::text, true);
  perform public.record_package(gen_random_uuid(), d1, null);
  perform public.record_visitor(gen_random_uuid(), d1, 'DT Misafir', null);
  reset role;
  if not exists (select 1 from public.audit_log where site_id = s and entity in ('packages', 'visitors')) then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: kargo/ziyaretçi işlem geçmişine yazıldı'; end if;

  raise exception 'SONUÇ: % test geçti, % test kaldı.%', gecti, kaldi,
    case when kaldi = 0 then ' Her şey yolunda.' else rapor end;
end;
$$;
