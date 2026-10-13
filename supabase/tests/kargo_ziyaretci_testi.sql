-- Kargo ve ziyaretçi testi: danışma kaydeder/teslim eder/çıkış yazar; tekrar gönderimde çift kayıt olmaz; geri alma ve silme sadece aynı gün;
-- sakin sadece kendi dairesinin kargosunu ve (son 30 gün) ziyaretçisini görür; kiracı varken malik ziyaretçileri görmez;
-- başka site göremez; sakin kayıt açamaz; 1 yıldan eski ziyaretçi silinir. Sonunda HER ŞEYİ GERİ ALIR.
-- Beklenen: "SONUÇ: 17 test geçti, 0 test kaldı. Her şey yolunda."
do $$
declare
  u_dan uuid := gen_random_uuid(); u_mal uuid := gen_random_uuid(); u_kir uuid := gen_random_uuid(); u_s2 uuid := gen_random_uuid(); u_dis uuid := gen_random_uuid();
  s_a uuid; s_b uuid; blk uuid; d1 uuid; d2 uuid; r uuid; pk uuid; v uuid; c uuid := gen_random_uuid(); n int; pl text;
  gecti int := 0; kaldi int := 0; rapor text := '';
begin
  insert into auth.users (id, email) values (u_dan, 'kz-dan@example.com'), (u_mal, 'kz-mal@example.com'), (u_kir, 'kz-kir@example.com'), (u_s2, 'kz-s2@example.com'), (u_dis, 'kz-dis@example.com');
  insert into public.sites (name, type) values ('KZ A', 'apartman') returning id into s_a;
  insert into public.sites (name, type) values ('KZ B', 'apartman') returning id into s_b;
  insert into public.memberships (user_id, site_id, role) values (u_dan, s_a, 'danisma'), (u_dis, s_b, 'danisma');
  insert into public.blocks (site_id, name) values (s_a, 'A') returning id into blk;
  insert into public.units (site_id, block_id, no) values (s_a, blk, '1') returning id into d1;
  insert into public.units (site_id, block_id, no) values (s_a, blk, '2') returning id into d2;
  insert into public.residents (site_id, full_name, phone, user_id) values (s_a, 'Malik', '905320005001', u_mal) returning id into r;
  insert into public.unit_residents (site_id, unit_id, resident_id, relation, started_on) values (s_a, d1, r, 'malik', current_date - 400);
  insert into public.residents (site_id, full_name, phone, user_id) values (s_a, 'Kiracı', '905320005002', u_kir) returning id into r;
  insert into public.unit_residents (site_id, unit_id, resident_id, relation, started_on) values (s_a, d1, r, 'kiraci', current_date - 10);
  insert into public.residents (site_id, full_name, phone, user_id) values (s_a, 'Komşu', '905320005003', u_s2) returning id into r;
  insert into public.unit_residents (site_id, unit_id, resident_id, relation, started_on) values (s_a, d2, r, 'malik', current_date - 400);
  -- Eski kayıtlar: 20 gün önce (kiracı taşınmadan önce) gelen kargo ve 2 yıl önceki ziyaretçi
  insert into public.packages (site_id, unit_id, client_id, received_at) values (s_a, d1, gen_random_uuid(), now() - interval '20 days');
  insert into public.visitors (site_id, unit_id, client_id, visitor_name, arrived_at) values (s_a, d1, gen_random_uuid(), 'Çok Eski', now() - interval '2 years');

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  pk := public.record_package(c, d1, 'Büyük koli');
  if public.record_package(c, d1, 'Büyük koli') = pk then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: kargo iki kez kaydedildi'; end if;
  perform public.deliver_package(pk, 'Kiracı');
  perform public.deliver_package(pk, 'Başkası'); -- ikinci teslim yok sayılır
  if (select delivered_to from public.packages where id = pk) = 'Kiracı' then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: teslim bilgisi yanlış'; end if;
  perform public.undo_package_delivery(pk);
  if (select delivered_at from public.packages where id = pk) is null then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: teslim geri alınmadı'; end if;
  v := public.record_visitor(gen_random_uuid(), d1, 'Ayşe Misafir', '34 abc 123');
  select plate into pl from public.visitors where id = v;
  if pl = '34ABC123' then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: plaka %s', pl); end if;
  perform public.mark_visitor_departed(v);
  perform public.undo_visitor_departure(v);
  if (select departed_at from public.visitors where id = v) is null then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: çıkış geri alınmadı'; end if;
  perform public.mark_visitor_departed(v);

  -- Aynı gün kuralı: eski kayıtlar silinemez / geri alınamaz
  reset role;
  update public.packages set received_at = now() - interval '2 days' where id = pk;
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  begin
    perform public.delete_package(pk);
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: eski kargo silindi';
  exception when sqlstate '22023' then gecti := gecti + 1;
  end;

  -- Başka sitenin danışması göremez, kayıt açamaz
  perform set_config('request.jwt.claims', json_build_object('sub', u_dis, 'role', 'authenticated')::text, true);
  select count(*) into n from public.packages where site_id = s_a; if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başka site kargoyu görüyor'; end if;
  select count(*) into n from public.visitors where site_id = s_a; if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başka site ziyaretçiyi görüyor'; end if;
  begin
    perform public.record_package(gen_random_uuid(), d1, null);
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başka site kargo kaydetti';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;

  -- Kiracı: kendi taşınmasından sonraki kargoyu görür (20 gün önceki eski kargoyu görmez), ziyaretçiyi görür
  perform set_config('request.jwt.claims', json_build_object('sub', u_kir, 'role', 'authenticated')::text, true);
  select count(*) into n from public.packages; if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: kiracı %s kargo görüyor (1 olmalı)', n); end if;
  select count(*) into n from public.visitors; if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: kiracı %s ziyaretçi görüyor (1 olmalı)', n); end if;
  begin
    perform public.record_visitor(gen_random_uuid(), d1, 'Sakin Kendi', null);
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: sakin ziyaretçi kaydı açtı';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;

  -- Malik: kargoları görür (ikisi), ama dairede kiracı varken ziyaretçileri görmez
  perform set_config('request.jwt.claims', json_build_object('sub', u_mal, 'role', 'authenticated')::text, true);
  select count(*) into n from public.packages; if n = 2 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: malik %s kargo görüyor (2 olmalı)', n); end if;
  select count(*) into n from public.visitors; if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: kiracı varken malik ziyaretçi görüyor'; end if;

  -- Komşu (başka daire) hiçbir şey görmez
  perform set_config('request.jwt.claims', json_build_object('sub', u_s2, 'role', 'authenticated')::text, true);
  select count(*) into n from public.packages; if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: komşu kargo görüyor'; end if;
  select count(*) into n from public.visitors; if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: komşu ziyaretçi görüyor'; end if;
  reset role;

  -- 1 yıldan eski ziyaretçi silinir
  perform public.purge_old_visitors();
  select count(*) into n from public.visitors where visitor_name = 'Çok Eski'; if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: eski ziyaretçi silinmedi'; end if;

  raise exception 'SONUÇ: % test geçti, % test kaldı.%', gecti, kaldi,
    case when kaldi = 0 then ' Her şey yolunda.' else rapor end;
end;
$$;
