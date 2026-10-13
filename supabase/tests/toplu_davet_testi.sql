-- Toplu davet testi: yönetici listeyi davet eder (30 gün, sakin rehbere eklenir), uygulamayı zaten kullanan atlanır,
-- hatalı satırda hiçbiri yazılmaz, danışma ve başka site yapamaz, gönderildi işareti. Sonunda HER ŞEY GERİ ALINIR.
-- Beklenen: "SONUÇ: 7 test geçti, 0 test kaldı. Her şey yolunda."
do $$
declare
  u_yon uuid := gen_random_uuid(); u_dan uuid := gen_random_uuid(); u_dis uuid := gen_random_uuid(); u_var uuid := gen_random_uuid();
  s uuid; s2 uuid; blk uuid; d1 uuid; d2 uuid; r uuid; n int; inv uuid; rows jsonb;
  gecti int := 0; kaldi int := 0; rapor text := '';
begin
  insert into auth.users (id, email) values (u_yon, 'td-yon@example.com'), (u_dan, 'td-dan@example.com'), (u_dis, 'td-dis@example.com'), (u_var, public.login_email('905320004003'));
  insert into public.sites (name, type) values ('TD Site', 'apartman') returning id into s;
  insert into public.sites (name, type) values ('TD Başka', 'apartman') returning id into s2;
  insert into public.memberships (user_id, site_id, role) values (u_yon, s, 'yonetici'), (u_dan, s, 'danisma'), (u_dis, s2, 'yonetici');
  insert into public.blocks (site_id, name) values (s, 'A') returning id into blk;
  insert into public.units (site_id, block_id, no) values (s, blk, '1') returning id into d1;
  insert into public.units (site_id, block_id, no) values (s, blk, '2') returning id into d2;
  insert into public.blocks (site_id, name) values (s2, 'B') returning id into blk;
  insert into public.units (site_id, block_id, no) values (s2, blk, '1');
  -- A-2'de uygulamayı zaten kullanan kişi
  insert into public.residents (site_id, full_name, phone, user_id) values (s, 'Zaten Var', '905320004003', u_var) returning id into r;
  insert into public.unit_residents (site_id, unit_id, resident_id) values (s, d2, r);

  rows := jsonb_build_array(
    jsonb_build_object('unit_id', d1, 'full_name', 'Toplu Bir', 'phone', '905320004001', 'relation', 'malik'),
    jsonb_build_object('unit_id', d1, 'full_name', 'Toplu İki', 'phone', '905320004002', 'relation', 'kiraci'),
    jsonb_build_object('unit_id', d2, 'full_name', 'Zaten Var', 'phone', '905320004003', 'relation', 'malik'));

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  select count(*) filter (where status = 'davet') into n from public.create_invites_bulk(s, rows);
  if n = 2 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: %s davet açıldı (2 olmalı)', n); end if;
  select count(*) into n from public.invites where site_id = s and role = 'sakin' and expires_at > now() + interval '29 days';
  if n = 2 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: toplu davet 30 gün değil'; end if;
  select count(*) into n from public.residents x join public.unit_residents ur on ur.resident_id = x.id where x.site_id = s and ur.unit_id = d1 and x.user_id is null;
  if n = 2 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: davet edilenler rehbere eklenmedi'; end if;

  -- Hatalı satır: hiçbiri yazılmaz
  select count(*) into n from public.invites where site_id = s;
  begin
    perform public.create_invites_bulk(s, jsonb_build_array(
      jsonb_build_object('unit_id', d1, 'full_name', 'Yeni Kişi', 'phone', '905320004009', 'relation', 'malik'),
      jsonb_build_object('unit_id', d1, 'full_name', 'Hatalı', 'phone', '123', 'relation', 'malik')));
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: hatalı liste kabul edildi';
  exception when sqlstate '22023' then
    if (select count(*) from public.invites where site_id = s) = n then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: hatalı listede bir kısmı yazıldı'; end if;
  end;

  -- Gönderildi işareti
  select id into inv from public.invites where site_id = s and phone = '905320004001';
  perform public.mark_invite_sent(inv);
  if (select sent_at from public.invites where id = inv) is not null then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: gönderildi işaretlenmedi'; end if;

  -- Danışma ve başka site yöneticisi yapamaz
  n := 0;
  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  begin perform public.create_invites_bulk(s, rows); exception when insufficient_privilege then n := n + 1; end;
  begin perform public.mark_invite_sent(inv); exception when insufficient_privilege then n := n + 1; end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_dis, 'role', 'authenticated')::text, true);
  begin perform public.create_invites_bulk(s, rows); exception when insufficient_privilege then n := n + 1; end;
  if n = 3 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: yetkisiz toplu davet (%s/3 engellendi)', n); end if;

  -- Başka sitenin dairesi listeye konamaz
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  begin
    perform public.create_invites_bulk(s, jsonb_build_array(jsonb_build_object('unit_id', (select id from public.units where site_id = s2 limit 1), 'full_name', 'Başka Site', 'phone', '905320004010', 'relation', 'malik')));
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başka sitenin dairesine davet açıldı';
  exception when others then gecti := gecti + 1;
  end;
  reset role;

  raise exception 'SONUÇ: % test geçti, % test kaldı.%', gecti, kaldi,
    case when kaldi = 0 then ' Her şey yolunda.' else rapor end;
end;
$$;
