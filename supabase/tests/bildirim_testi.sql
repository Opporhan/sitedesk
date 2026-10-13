-- Bildirim testi: telefon kaydı (herkes kendi telefonunu görür), kime bildirim kuyruğa girer (gerçek gönderim yok; sonunda HER ŞEY GERİ ALINIR).
-- Beklenen: "SONUÇ: 8 test geçti, 0 test kaldı. Her şey yolunda."
do $$
declare
  u_yon uuid := gen_random_uuid(); u_dan uuid := gen_random_uuid(); u_sak uuid := gen_random_uuid();
  s uuid; blk uuid; d uuid; r uuid; t uuid; n int; before int; msg text;
  gecti int := 0; kaldi int := 0; rapor text := '';
begin
  insert into auth.users (id, email) values (u_yon, 'bt-yon@example.com'), (u_dan, 'bt-dan@example.com'), (u_sak, 'bt-sak@example.com');
  insert into public.sites (name, type) values ('BT Site', 'apartman') returning id into s;
  insert into public.memberships (user_id, site_id, role) values (u_yon, s, 'yonetici'), (u_dan, s, 'danisma');
  insert into public.blocks (site_id, name) values (s, 'A') returning id into blk;
  insert into public.units (site_id, block_id, no) values (s, blk, '3') returning id into d;
  insert into public.residents (site_id, full_name, phone, user_id) values (s, 'BT Sakin', '905320006001', u_sak) returning id into r;
  insert into public.unit_residents (site_id, unit_id, resident_id) values (s, d, r);

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  perform public.register_push_token('ExponentPushToken[yonetici-test]', 'android');
  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  perform public.register_push_token('ExponentPushToken[danisma-test]', 'android');
  perform set_config('request.jwt.claims', json_build_object('sub', u_sak, 'role', 'authenticated')::text, true);
  perform public.register_push_token('ExponentPushToken[sakin-test]', 'android');
  select count(*) into n from public.push_tokens; if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: sakin %s telefon görüyor (1 olmalı)', n); end if;
  begin
    perform public.register_push_token('geçersiz', 'android');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: geçersiz kimlik kaydedildi';
  exception when check_violation then gecti := gecti + 1;
  end;

  -- Sakin acil kayıt açar → sadece yöneticiye (danışmaya ve sakinin kendisine değil)
  reset role; select count(*) into before from net.http_request_queue; set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_sak, 'role', 'authenticated')::text, true);
  t := public.create_ticket(gen_random_uuid(), d, 'ariza', 'daire', 'Su baskını', null, true);
  reset role;
  select count(*) into n from net.http_request_queue;
  select convert_from(q.body, 'utf8') into msg from net.http_request_queue q order by id desc limit 1;
  if n = before + 1 and msg like '%yonetici-test%' and msg not like '%danisma-test%' and msg not like '%sakin-test%' and msg like '%ACİL · A-3%' then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: yeni kayıt bildirimi yanlış: %s', msg); end if;

  -- Danışma durum değiştirir → sakine
  select count(*) into before from net.http_request_queue; set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  perform public.set_ticket_status(t, 'yapiliyor', 'Tesisatçı geliyor');
  reset role;
  select convert_from(q.body, 'utf8') into msg from net.http_request_queue q order by id desc limit 1;
  if msg like '%sakin-test%' and msg like '%Yapılıyor%' and msg not like '%yonetici-test%' then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: durum bildirimi yanlış: %s', msg); end if;

  -- Yönetici cevap yazar → sakine
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  perform public.add_ticket_note(t, 'Yarın 10 gibi gelinecek');
  reset role;
  select convert_from(q.body, 'utf8') into msg from net.http_request_queue q order by id desc limit 1;
  if msg like '%sakin-test%' and msg like '%Yönetimden cevap%' then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: cevap bildirimi yanlış: %s', msg); end if;

  -- Sakin not yazar → bildirim yok
  select count(*) into before from net.http_request_queue; set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_sak, 'role', 'authenticated')::text, true);
  perform public.add_ticket_note(t, 'Teşekkürler');
  reset role;
  select count(*) into n from net.http_request_queue;
  if n = before then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: sakinin notu bildirim gönderdi'; end if;

  -- Tamamlandı → sakin "devam ediyor" → yöneticiye
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  perform public.set_ticket_status(t, 'tamamlandi');
  perform set_config('request.jwt.claims', json_build_object('sub', u_sak, 'role', 'authenticated')::text, true);
  perform public.resolve_ticket(t, false, 'Hâlâ akıyor');
  reset role;
  select convert_from(q.body, 'utf8') into msg from net.http_request_queue q order by id desc limit 1;
  if msg like '%yonetici-test%' and msg like '%Sorun devam ediyor%' then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: devam bildirimi yanlış: %s', msg); end if;

  -- Kargo → sakine
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  perform public.record_package(gen_random_uuid(), d, null);
  reset role;
  select convert_from(q.body, 'utf8') into msg from net.http_request_queue q order by id desc limit 1;
  if msg like '%sakin-test%' and msg like '%Kargonuz geldi%' then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: kargo bildirimi yanlış: %s', msg); end if;

  raise exception 'SONUÇ: % test geçti, % test kaldı.%', gecti, kaldi,
    case when kaldi = 0 then ' Her şey yolunda.' else rapor end;
end;
$$;
