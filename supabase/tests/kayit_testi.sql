-- Kayıt (arıza/talep) testi: kim açabilir, aynı kayıt iki kez açılmaz, kim görür (daire, site ayrımı), not/durum/sonuç yetkileri,
-- fotoğraf/video sınırı, dosya deposu erişimi. Sonunda HER ŞEYİ GERİ ALIR. Beklenen: "SONUÇ: 21 test geçti, 0 test kaldı. Her şey yolunda."
do $$
declare
  u_yon uuid := gen_random_uuid(); u_dan uuid := gen_random_uuid(); u_s1 uuid := gen_random_uuid(); u_s1b uuid := gen_random_uuid();
  u_s2 uuid := gen_random_uuid(); u_byon uuid := gen_random_uuid();
  s_a uuid; s_b uuid; blk uuid; d1 uuid; d2 uuid; r1 uuid; r1b uuid; r2 uuid; t uuid; t2 uuid; c uuid := gen_random_uuid(); n int; st text;
  gecti int := 0; kaldi int := 0; rapor text := '';
begin
  insert into auth.users (id, email) values (u_yon, 'kt-yon@example.com'), (u_dan, 'kt-dan@example.com'), (u_s1, 'kt-s1@example.com'),
    (u_s1b, 'kt-s1b@example.com'), (u_s2, 'kt-s2@example.com'), (u_byon, 'kt-byon@example.com');
  insert into public.sites (name, type) values ('KT A', 'apartman') returning id into s_a;
  insert into public.sites (name, type) values ('KT B', 'apartman') returning id into s_b;
  insert into public.memberships (user_id, site_id, role) values (u_yon, s_a, 'yonetici'), (u_dan, s_a, 'danisma'), (u_byon, s_b, 'yonetici');
  insert into public.blocks (site_id, name) values (s_a, 'A') returning id into blk;
  insert into public.units (site_id, block_id, no) values (s_a, blk, '1') returning id into d1;
  insert into public.units (site_id, block_id, no) values (s_a, blk, '2') returning id into d2;
  insert into public.residents (site_id, full_name, phone, user_id) values (s_a, 'Sakin Bir', '905320002001', u_s1) returning id into r1;
  insert into public.residents (site_id, full_name, phone, user_id) values (s_a, 'Sakin Hane', '905320002002', u_s1b) returning id into r1b;
  insert into public.residents (site_id, full_name, phone, user_id) values (s_a, 'Sakin İki', '905320002003', u_s2) returning id into r2;
  insert into public.unit_residents (site_id, unit_id, resident_id, relation) values (s_a, d1, r1, 'malik'), (s_a, d1, r1b, 'kiraci'), (s_a, d2, r2, 'kiraci');

  set local role authenticated;

  -- Sakin kendi dairesi için kayıt açar; aynı client_id ile ikinci kayıt açılmaz; başka daireye açamaz
  perform set_config('request.jwt.claims', json_build_object('sub', u_s1, 'role', 'authenticated')::text, true);
  t := public.create_ticket(c, d1, 'ariza', 'daire', 'Musluk damlatıyor', 'Dünden beri', true);
  if public.create_ticket(c, d1, 'ariza', 'daire', 'Musluk damlatıyor', 'Dünden beri', true) = t then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: aynı kayıt iki kez açıldı'; end if;
  select created_by_role into st from public.tickets where id = t;
  if st = 'sakin' then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: kayıt rolü yanlış'; end if;
  begin
    perform public.create_ticket(gen_random_uuid(), d2, 'talep', 'daire', 'Başkasının dairesi', null, false);
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: sakin başka daireye kayıt açtı';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;
  begin
    insert into public.tickets (site_id, unit_id, client_id, kind, location, title, created_by_role) values (s_a, d1, gen_random_uuid(), 'talep', 'ortak', 'Doğrudan', 'sakin');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: tabloya doğrudan yazıldı';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;

  -- Fotoğraf/video: yol kayda ait olmalı, dosya yüklenmiş olmalı, en fazla 5 fotoğraf ya da 1 video
  reset role;
  insert into storage.objects (bucket_id, name) select 'kayitlar', s_a || '/' || t || '/f' || g || '.jpg' from generate_series(1, 6) g;
  insert into storage.objects (bucket_id, name) values ('kayitlar', s_a || '/' || t || '/v.mp4');
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_s1, 'role', 'authenticated')::text, true);
  begin
    perform public.add_ticket_media(t, s_b || '/' || t || '/x.jpg', 'foto', 1000, null);
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başka sitenin yolu kabul edildi';
  exception when sqlstate '22023' then gecti := gecti + 1;
  end;
  begin
    perform public.add_ticket_media(t, s_a || '/' || t || '/yok.jpg', 'foto', 1000, null);
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: yüklenmemiş dosya kaydedildi';
  exception when sqlstate '22023' then gecti := gecti + 1;
  end;
  perform public.add_ticket_media(t, s_a || '/' || t || '/f1.jpg', 'foto', 1000, null);
  perform public.add_ticket_media(t, s_a || '/' || t || '/f2.jpg', 'foto', 1000, null);
  perform public.add_ticket_media(t, s_a || '/' || t || '/f3.jpg', 'foto', 1000, null);
  perform public.add_ticket_media(t, s_a || '/' || t || '/f4.jpg', 'foto', 1000, null);
  perform public.add_ticket_media(t, s_a || '/' || t || '/f5.jpg', 'foto', 1000, null);
  perform public.add_ticket_media(t, s_a || '/' || t || '/f5.jpg', 'foto', 1000, null); -- tekrar gönderim: hata vermez, çift saymaz
  select count(*) into n from public.ticket_media where ticket_id = t;
  if n = 5 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: %s dosya kaydı (5 olmalı)', n); end if;
  begin
    perform public.add_ticket_media(t, s_a || '/' || t || '/f6.jpg', 'foto', 1000, null);
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: 6. fotoğraf eklendi';
  exception when sqlstate 'SD011' then gecti := gecti + 1;
  end;
  begin
    perform public.add_ticket_media(t, s_a || '/' || t || '/v.mp4', 'video', 5000000, 20000);
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: fotoğrafların yanına video eklendi';
  exception when sqlstate 'SD011' then gecti := gecti + 1;
  end;
  select count(*) into n from storage.objects where bucket_id = 'kayitlar' and name like s_a || '/' || t || '/%';
  if n = 7 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: sakin kendi dosyalarını göremiyor (%s)', n); end if;

  -- Aynı dairedeki hane üyesi kaydı ve dosyaları görür; başka dairenin sakini göremez
  perform set_config('request.jwt.claims', json_build_object('sub', u_s1b, 'role', 'authenticated')::text, true);
  select count(*) into n from public.tickets where id = t; if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: hane üyesi daire kaydını görmüyor'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', u_s2, 'role', 'authenticated')::text, true);
  select count(*) into n from public.tickets; if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başka dairenin sakini kaydı görüyor'; end if;
  select count(*) into n from storage.objects where bucket_id = 'kayitlar'; if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başka dairenin sakini dosyaları görüyor'; end if;
  select count(*) into n from public.ticket_events where ticket_id = t; if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başka dairenin sakini notları görüyor'; end if;

  -- Başka sitenin yöneticisi göremez, açamaz
  perform set_config('request.jwt.claims', json_build_object('sub', u_byon, 'role', 'authenticated')::text, true);
  select count(*) into n from public.tickets where site_id = s_a; if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başka site yöneticisi kaydı görüyor'; end if;
  begin
    perform public.create_ticket(gen_random_uuid(), d1, 'ariza', 'daire', 'Sızma', null, false);
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başka site yöneticisi kayıt açtı';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;

  -- Danışma (07.10.2026): görür, not yazar, durumu değiştirir; sakin adına kayıt açabilir
  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  perform public.add_ticket_note(t, 'Tesisatçıya haber verildi');
  perform public.set_ticket_status(t, 'yapiliyor');
  select status into st from public.tickets where id = t;
  if st = 'yapiliyor' then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: danışma durumu değiştiremedi'; end if;
  t2 := public.create_ticket(gen_random_uuid(), d2, 'talep', 'ortak', 'Bahçe sulaması', null, false);
  select created_by_role into st from public.tickets where id = t2;
  if st = 'danisma' then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: danışma sakin adına kayıt açamadı'; end if;

  -- Yönetici tamamlar; sakin "devam ediyor" der → inceleniyor'a döner; notlar sakine görünür
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  perform public.set_ticket_status(t, 'tamamlandi', 'Conta değiştirildi');
  perform set_config('request.jwt.claims', json_build_object('sub', u_s1, 'role', 'authenticated')::text, true);
  perform public.resolve_ticket(t, false, 'Hâlâ damlatıyor');
  select status into st from public.tickets where id = t;
  if st = 'inceleniyor' then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: devam sonrası durum %s', st); end if;
  select count(*) into n from public.ticket_events where ticket_id = t;
  if n = 5 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: sakin %s olay görüyor (5 olmalı)', n); end if;
  begin
    perform public.set_ticket_status(t, 'tamamlandi');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: sakin durumu değiştirdi';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;
  reset role;

  raise exception 'SONUÇ: % test geçti, % test kaldı.%', gecti, kaldi,
    case when kaldi = 0 then ' Her şey yolunda.' else rapor end;
end;
$$;
