-- Katılma güvenliği testi: rehberdeki (davet edilmiş) numara site koduyla katılamaz ve onaylanamaz; rehberde olmayan katılır;
-- hesap açma sınırı (aynı adres saatte 20) ve uygulama sınır fonksiyonunu çağıramaz; siteyi açan yöneticinin erişimini
-- diğer yönetici kapatamaz, sistem yöneticisi kapatır. Sonunda HER ŞEY GERİ ALINIR.
-- Beklenen: "SONUÇ: 8 test geçti, 0 test kaldı. Her şey yolunda."
do $$
declare
  u_kur uuid := gen_random_uuid(); u_yon2 uuid := gen_random_uuid(); u_sahte uuid := gen_random_uuid(); u_yeni uuid := gen_random_uuid();
  u_adm uuid;
  s uuid; blk uuid; d1 uuid; d2 uuid; code text; req uuid; n int; ok boolean;
  gecti int := 0; kaldi int := 0; rapor text := '';
begin
  insert into auth.users (id, email) values (u_kur, public.login_email('905320004001')), (u_yon2, public.login_email('905320004002')),
    (u_sahte, public.login_email('905320004003')), (u_yeni, public.login_email('905320004004'));

  -- Kurucu siteyi kendisi açar (created_by = kurucu, yönetici olur)
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_kur, 'role', 'authenticated')::text, true);
  s := public.create_site('KG Site', 'apartman', null);
  reset role;
  select join_code into code from public.sites where id = s;
  insert into public.memberships (user_id, site_id, role) values (u_yon2, s, 'yonetici');
  insert into public.blocks (site_id, name) values (s, 'A') returning id into blk;
  insert into public.units (site_id, block_id, no) values (s, blk, '1') returning id into d1;
  insert into public.units (site_id, block_id, no) values (s, blk, '2') returning id into d2;

  -- Yönetici 905320004003 numarasını A-1'e davet eder (rehbere "uygulamada değil" olarak girer)
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_kur, 'role', 'authenticated')::text, true);
  perform public.create_invite(s, 'sakin', 'Gerçek Ahmet', '905320004003', d1, 'malik');

  -- 1: o numarayla açılmış hesap site koduyla katılamaz
  perform set_config('request.jwt.claims', json_build_object('sub', u_sahte, 'role', 'authenticated')::text, true);
  begin
    perform public.request_join(code, d2, 'Gerçek Ahmet', 'malik');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: davet edilen numara site koduyla istek gönderdi';
  exception when sqlstate 'SD063' then gecti := gecti + 1;
  end;

  -- 2: istek davetten önce gönderilmişse yönetici onaylayamaz (rehber kaydına bağlanmaz)
  perform set_config('request.jwt.claims', json_build_object('sub', u_yeni, 'role', 'authenticated')::text, true);
  req := public.request_join(code, d2, 'Yeni Komşu', 'kiraci');
  perform set_config('request.jwt.claims', json_build_object('sub', u_kur, 'role', 'authenticated')::text, true);
  perform public.create_invite(s, 'sakin', 'Yeni Komşu', '905320004004', d1, 'malik');
  begin
    perform public.decide_join(req, true);
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: davet edilen numaranın isteği onaylandı';
  exception when sqlstate 'SD063' then gecti := gecti + 1;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_yeni, 'role', 'authenticated')::text, true);
  if (select count(*) from public.units where site_id = s) = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: onaylanamayan kişi daireyi görüyor'; end if;

  -- 3: uygulama hesap açma sınırını çağıramaz
  begin
    perform public.allow_signup('x');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: uygulama allow_signup çağırdı';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;
  reset role;

  -- 4: aynı adresten saatte 20 hesap, 21. reddedilir; başka adres etkilenmez
  n := 0;
  for i in 1 .. 21 loop
    ok := public.allow_signup('kg-test-adres');
    if ok then n := n + 1; end if;
  end loop;
  if n = 20 and public.allow_signup('kg-baska-adres') then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: hesap açma sınırı yanlış (%s izin)', n); end if;

  -- 5: ikinci yönetici kurucunun erişimini kapatamaz
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon2, 'role', 'authenticated')::text, true);
  update public.memberships set ended_on = current_date where site_id = s and user_id = u_kur; get diagnostics n = row_count;
  if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: ikinci yönetici kurucuyu çıkardı'; end if;

  -- 6: kurucu ikinci yöneticinin erişimini kapatabilir
  perform set_config('request.jwt.claims', json_build_object('sub', u_kur, 'role', 'authenticated')::text, true);
  update public.memberships set ended_on = current_date where site_id = s and user_id = u_yon2; get diagnostics n = row_count;
  if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: kurucu ikinci yöneticiyi çıkaramadı'; end if;
  reset role;

  -- 7: sistem yöneticisi kurucunun erişimini kapatabilir
  select user_id into u_adm from public.platform_admins limit 1;
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role', 'authenticated')::text, true);
  update public.memberships set ended_on = current_date where site_id = s and user_id = u_kur; get diagnostics n = row_count;
  if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: sistem yöneticisi kurucuyu çıkaramadı'; end if;
  reset role;

  raise exception 'SONUÇ: % test geçti, % test kaldı.%', gecti, kaldi,
    case when kaldi = 0 then ' Her şey yolunda.' else rapor end;
end;
$$;
