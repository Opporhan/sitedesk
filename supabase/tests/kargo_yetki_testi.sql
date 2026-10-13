-- Kargo yetki testi (08.10.2026): kargoyu sadece danışma kaydeder/görür/teslim eder ve sakine yeniden haber verir;
-- sakin kendi kargosunu görür; yönetici ve sistem yöneticisi kargoyu ve misafirleri göremez; yönetici sadece hizmet (tamir/servis) girişlerini görür.
-- Sonunda HER ŞEY GERİ ALINIR. Beklenen: "SONUÇ: 9 test geçti, 0 test kaldı. Her şey yolunda."
do $$
declare
  u_adm uuid := gen_random_uuid(); u_yon uuid := gen_random_uuid(); u_dan uuid := gen_random_uuid(); u_sak uuid := gen_random_uuid();
  s uuid; blk uuid; d1 uuid; r uuid; pk uuid; n int; before int; msg text;
  gecti int := 0; kaldi int := 0; rapor text := '';
begin
  insert into auth.users (id, email) values (u_adm, 'ky-adm@example.com'), (u_yon, 'ky-yon@example.com'), (u_dan, 'ky-dan@example.com'), (u_sak, 'ky-sak@example.com');
  insert into public.platform_admins (user_id) values (u_adm);
  insert into public.sites (name, type) values ('KY Site', 'apartman') returning id into s;
  insert into public.memberships (user_id, site_id, role) values (u_yon, s, 'yonetici'), (u_dan, s, 'danisma');
  insert into public.blocks (site_id, name) values (s, 'A') returning id into blk;
  insert into public.units (site_id, block_id, no) values (s, blk, '1') returning id into d1;
  insert into public.residents (site_id, full_name, phone, user_id) values (s, 'KY Sakin', '905320006101', u_sak) returning id into r;
  insert into public.unit_residents (site_id, unit_id, resident_id, started_on) values (s, d1, r, current_date - 10);
  insert into public.push_tokens (token, user_id, platform) values ('ExponentPushToken[ky-sakin]', u_sak, 'android');

  set local role authenticated;
  -- Danışma kaydeder, görür
  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  pk := public.record_package(gen_random_uuid(), d1, 'Koli');
  perform public.record_visitor(gen_random_uuid(), d1, 'KY Misafir', null);
  perform public.record_visitor(gen_random_uuid(), d1, 'KY Klima Servisi', '34srv77', 'hizmet');
  select count(*) into n from public.packages where site_id = s;
  if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: danışma kargoyu görmüyor'; end if;

  -- Danışma yeniden haber verir → sakine bildirim; saat dolmadan ikinci kez olmaz
  reset role; select count(*) into before from net.http_request_queue; set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  perform public.remind_package(pk);
  reset role;
  select convert_from(q.body, 'utf8') into msg from net.http_request_queue q order by id desc limit 1;
  if msg like '%ky-sakin%' and msg like '%danışmada bekliyor%' then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: hatırlatma bildirimi yanlış: %s', msg); end if;
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  begin
    perform public.remind_package(pk);
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: aynı saat içinde ikinci hatırlatma gitti';
  exception when sqlstate 'SD030' then gecti := gecti + 1;
  end;

  -- Sakin kendi kargosunu görür
  perform set_config('request.jwt.claims', json_build_object('sub', u_sak, 'role', 'authenticated')::text, true);
  select count(*) into n from public.packages where id = pk;
  if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: sakin kendi kargosunu görmüyor'; end if;

  -- Yönetici: kargoyu ve kargo geçmişini görmez, kargo işlemi yapamaz; misafirleri görmez, sadece hizmet girişlerini görür
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  select count(*) into n from public.packages where site_id = s;
  if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: yönetici kargoyu görüyor'; end if;
  reset role; select count(*) into n from public.audit_log where site_id = s and entity = 'packages'; set local role authenticated;
  if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: yönetici kargo geçmişini görüyor'; end if;
  n := 0;
  begin perform public.record_package(gen_random_uuid(), d1, null); exception when insufficient_privilege then n := n + 1; end;
  begin perform public.deliver_package(pk, 'x'); exception when insufficient_privilege then n := n + 1; end;
  begin perform public.remind_package(pk); exception when insufficient_privilege then n := n + 1; end;
  if n = 3 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: yönetici kargo işlemi yaptı (%s/3 engellendi)', n); end if;
  select count(*) into n from public.visitors where site_id = s;
  if n = 1 and (select visitor_name from public.visitors where site_id = s) = 'KY Klima Servisi' then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: yönetici misafiri görüyor ya da hizmet girişini görmüyor (%s)', n); end if;

  -- Sistem yöneticisi de kargoyu görmez
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role', 'authenticated')::text, true);
  select count(*) into n from public.packages where site_id = s;
  if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: sistem yöneticisi kargoyu görüyor'; end if;
  reset role;

  raise exception 'SONUÇ: % test geçti, % test kaldı.%', gecti, kaldi,
    case when kaldi = 0 then ' Her şey yolunda.' else rapor end;
end;
$$;
