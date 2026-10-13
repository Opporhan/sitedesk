-- Sitelerim testi: yönetici sadece yönettiği aktif siteleri doğru sayılarla görür; başka sitenin yöneticisi, danışma ve sakin
-- görmez; sistem yöneticisi kapalı siteler dahil hepsini görür. Sonunda HER ŞEY GERİ ALINIR.
-- Beklenen: "SONUÇ: 6 test geçti, 0 test kaldı. Her şey yolunda."
do $$
declare
  u_adm uuid := gen_random_uuid(); u_yon uuid := gen_random_uuid(); u_dis uuid := gen_random_uuid(); u_dan uuid := gen_random_uuid(); u_sak uuid := gen_random_uuid();
  s1 uuid; s2 uuid; s3 uuid; kapali uuid; blk uuid; d1 uuid; r uuid; j jsonb; e jsonb;
  gecti int := 0; kaldi int := 0; rapor text := '';
begin
  insert into auth.users (id, email) values (u_adm, 'sl-adm@example.com'), (u_yon, 'sl-yon@example.com'), (u_dis, 'sl-dis@example.com'), (u_dan, 'sl-dan@example.com'), (u_sak, 'sl-sak@example.com');
  insert into public.platform_admins (user_id) values (u_adm);
  insert into public.sites (name, type) values ('SL Bir', 'apartman') returning id into s1;
  insert into public.sites (name, type) values ('SL İki', 'villa') returning id into s2;
  insert into public.sites (name, type) values ('SL Başka', 'apartman') returning id into s3;
  insert into public.sites (name, type, active) values ('SL Kapalı', 'apartman', false) returning id into kapali;
  insert into public.memberships (user_id, site_id, role) values (u_yon, s1, 'yonetici'), (u_yon, s2, 'yonetici'), (u_yon, kapali, 'yonetici'), (u_dis, s3, 'yonetici'), (u_dan, s1, 'danisma');
  insert into public.blocks (site_id, name) values (s1, 'A') returning id into blk;
  insert into public.units (site_id, block_id, no) values (s1, blk, '1') returning id into d1;
  insert into public.residents (site_id, full_name, phone, user_id) values (s1, 'SL Sakin', '905320009001', u_sak) returning id into r;
  insert into public.unit_residents (site_id, unit_id, resident_id) values (s1, d1, r);
  -- S1: 3 açık kayıt (1 acil, 2 yeni), 1 tamamlanmış; 2 bekleyen + 1 teslim kargo; 1 içeride + 1 çıkmış + 1 eski ziyaretçi
  insert into public.tickets (site_id, unit_id, client_id, kind, location, title, urgent, status, created_by_role) values
    (s1, d1, gen_random_uuid(), 'ariza', 'daire', 'Acil iş', true, 'alindi', 'sakin'),
    (s1, d1, gen_random_uuid(), 'ariza', 'daire', 'Yeni iş', false, 'alindi', 'sakin'),
    (s1, d1, gen_random_uuid(), 'talep', 'daire', 'Süren iş', false, 'yapiliyor', 'sakin'),
    (s1, d1, gen_random_uuid(), 'talep', 'daire', 'Biten iş', false, 'tamamlandi', 'sakin');
  insert into public.packages (site_id, unit_id, client_id) values (s1, d1, gen_random_uuid()), (s1, d1, gen_random_uuid());
  insert into public.packages (site_id, unit_id, client_id, delivered_at) values (s1, d1, gen_random_uuid(), now());
  insert into public.visitors (site_id, unit_id, client_id, visitor_name) values (s1, d1, gen_random_uuid(), 'İçerideki');
  insert into public.visitors (site_id, unit_id, client_id, visitor_name, departed_at) values (s1, d1, gen_random_uuid(), 'Çıkan', now());
  insert into public.visitors (site_id, unit_id, client_id, visitor_name, arrived_at) values (s1, d1, gen_random_uuid(), 'Eski', now() - interval '10 days');

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  j := public.my_sites_overview();
  if jsonb_array_length(j) = 2 and not j @> jsonb_build_array(jsonb_build_object('site_id', kapali)) and not j @> jsonb_build_array(jsonb_build_object('site_id', s3)) then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: yönetici yanlış siteleri görüyor: %s', j); end if;
  select x into e from jsonb_array_elements(j) x where x ->> 'site_id' = s1::text;
  if (e ->> 'open_tickets')::int = 3 and (e ->> 'urgent_open')::int = 1 and (e ->> 'new_tickets')::int = 2 and not (e ? 'waiting_packages') and not (e ? 'inside_visitors') then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: sayılar yanlış: %s', e); end if;

  perform set_config('request.jwt.claims', json_build_object('sub', u_dis, 'role', 'authenticated')::text, true);
  j := public.my_sites_overview();
  if jsonb_array_length(j) = 1 and j -> 0 ->> 'site_id' = s3::text then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başka site yöneticisi yanlış görüyor'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  if jsonb_array_length(public.my_sites_overview()) = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: danışma site özetini görüyor'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', u_sak, 'role', 'authenticated')::text, true);
  if jsonb_array_length(public.my_sites_overview()) = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: sakin site özetini görüyor'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role', 'authenticated')::text, true);
  j := public.my_sites_overview();
  if j @> jsonb_build_array(jsonb_build_object('site_id', kapali, 'active', false)) and j @> jsonb_build_array(jsonb_build_object('site_id', s3)) then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: sistem yöneticisi bütün siteleri görmüyor'; end if;
  reset role;

  raise exception 'SONUÇ: % test geçti, % test kaldı.%', gecti, kaldi,
    case when kaldi = 0 then ' Her şey yolunda.' else rapor end;
end;
$$;
