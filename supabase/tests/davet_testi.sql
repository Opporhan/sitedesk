-- Davet ve giriş testi (adım 3): kim kimi davet edebilir, davet önizleme, kabul (telefon eşleşmesi, tek kullanım),
-- bir dairede birden çok kişi / bir kişi birden çok dairede, taşınınca erişimin kapanması, site ayrımı, işlem geçmişi.
-- Sonunda HER ŞEYİ GERİ ALIR. Beklenen: "SONUÇ: 24 test geçti, 0 test kaldı. Her şey yolunda."
do $$
declare
  u_adm uuid := gen_random_uuid(); u_yon uuid := gen_random_uuid(); u_dan uuid := gen_random_uuid();
  u_s1 uuid := gen_random_uuid(); u_s2 uuid := gen_random_uuid(); u_yab uuid := gen_random_uuid(); u_bdan uuid := gen_random_uuid();
  s_a uuid; s_b uuid; b_a uuid; d1 uuid; d2 uuid; b_b uuid; d_b uuid;
  inv record; inv2 record; inv3 record; j jsonb; n int; ur uuid;
  gecti int := 0; kaldi int := 0; rapor text := '';
begin
  insert into auth.users (id, email) values
    (u_adm, 'dt-adm@example.com'), (u_yon, public.login_email('905320001001')), (u_dan, public.login_email('905320001002')),
    (u_s1, public.login_email('905320001003')), (u_s2, public.login_email('905320001004')), (u_yab, public.login_email('905320001005')),
    (u_bdan, public.login_email('905320001006'));
  insert into public.platform_admins (user_id) values (u_adm);
  insert into public.sites (name, type) values ('DT A', 'apartman') returning id into s_a;
  insert into public.sites (name, type) values ('DT B', 'villa') returning id into s_b;
  insert into public.memberships (user_id, site_id, role) values (u_yon, s_a, 'yonetici'), (u_dan, s_a, 'danisma'), (u_bdan, s_b, 'danisma');
  insert into public.blocks (site_id, name) values (s_a, 'A') returning id into b_a;
  insert into public.units (site_id, block_id, no) values (s_a, b_a, '1') returning id into d1;
  insert into public.units (site_id, block_id, no) values (s_a, b_a, '2') returning id into d2;
  insert into public.blocks (site_id, name) values (s_b, 'V') returning id into b_b;
  insert into public.units (site_id, block_id, no, type) values (s_b, b_b, '1', 'villa') returning id into d_b;

  set local role authenticated;

  -- Yetkiler (07.10.2026): davet sadece yönetimde — danışma sakin de davet edemez; yönetici yönetici davet edemez
  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  begin
    perform public.create_invite(s_a, 'sakin', 'Sakin Bir', '905320001003', d1, 'malik');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: danışma sakin davet etti';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;
  begin
    perform public.create_invite(s_a, 'danisma', 'Yeni Danışma', '905320001009');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: danışma danışma davet etti';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  select * into inv from public.create_invite(s_a, 'sakin', 'Sakin Bir', '905320001003', d1, 'malik');
  begin
    perform public.create_invite(s_b, 'yonetici', 'Yeni Yönetici', '905320001009');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: yönetici başka siteye yönetici davet etti';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;
  begin
    perform public.create_invite(s_a, 'sakin', 'Yanlış Daire', '905320001009', d_b, 'malik');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başka sitenin dairesine davet açıldı';
  exception when sqlstate '22023' then gecti := gecti + 1;
  end;
  -- Yönetici aynı kişiyi ikinci daireye (D2) de davet eder; ayrıca D1'e ikinci bir kişi
  select * into inv2 from public.create_invite(s_a, 'sakin', 'Sakin Bir', '905320001003', d2, 'kiraci');
  select * into inv3 from public.create_invite(s_a, 'sakin', 'Sakin İki', '905320001004', d1, 'kiraci');
  perform set_config('request.jwt.claims', json_build_object('sub', u_bdan, 'role', 'authenticated')::text, true);
  begin
    perform public.create_invite(s_a, 'sakin', 'Sızma', '905320001009', d1, 'malik');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başka sitenin danışması bu siteye davet açtı';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;
  select count(*) into n from public.invites where site_id = s_a;
  if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başka sitenin danışması davetleri görüyor'; end if;

  -- Önizleme girişsiz çalışır, telefonun sadece son 4 hanesi görünür
  reset role; set local role anon;
  j := public.invite_preview(inv.code);
  if (j ->> 'valid')::boolean and j ->> 'phone_last4' = '1003' and j ->> 'unit_label' = 'A-1' and not (j ? 'phone') then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: önizleme yanlış: %s', j); end if;
  begin
    perform public.accept_invite(inv.code);
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: girişsiz kişi daveti kabul etti';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;
  reset role; set local role authenticated;

  -- Başka telefonla giren kişi daveti kabul edemez
  perform set_config('request.jwt.claims', json_build_object('sub', u_yab, 'role', 'authenticated')::text, true);
  begin
    perform public.accept_invite(inv.code);
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: yabancı telefon daveti kabul etti';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;

  -- Doğru kişi kabul eder (kod ile ve bağlantı anahtarıyla); ikinci kez kullanılamaz
  perform set_config('request.jwt.claims', json_build_object('sub', u_s1, 'role', 'authenticated')::text, true);
  j := public.accept_invite(inv.code);
  perform public.accept_invite(inv2.token);
  if j ->> 'role' = 'sakin' then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: kabul sonucu yanlış'; end if;
  begin
    perform public.accept_invite(inv.code);
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: davet iki kez kullanıldı';
  exception when sqlstate '22023' then gecti := gecti + 1;
  end;
  j := public.my_context();
  if jsonb_array_length(j -> 'units') = 2 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: kişi 2 daireye bağlanmadı: %s', j); end if;
  select count(*) into n from public.residents where site_id = s_a and phone = '905320001003';
  if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: aynı telefon iki sakin kaydı oldu'; end if;
  -- Sakin kendi dairelerini görür, başka siteyi ve davetleri, işlem geçmişini göremez
  select count(*) into n from public.units; if n = 2 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: sakin %s daire görüyor', n); end if;
  select count(*) into n from public.invites; if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: sakin davetleri görüyor'; end if;
  begin perform count(*) from public.audit_log; kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: sakin işlem geçmişini okuyabiliyor';
  exception when insufficient_privilege then gecti := gecti + 1; end;
  begin
    insert into public.units (site_id, block_id, no) values (s_a, b_a, '99');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: sakin daire ekledi';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;

  -- Bir dairede ikinci kişi
  perform set_config('request.jwt.claims', json_build_object('sub', u_s2, 'role', 'authenticated')::text, true);
  perform public.accept_invite(inv3.code);
  select count(*) into n from public.units; if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: ikinci sakin %s daire görüyor', n); end if;

  -- Yönetici: taşınan kişinin D1 erişimini kapatır; işlem geçmişini görür; danışma kapatamaz
  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  select ur2.id into ur from public.unit_residents ur2 join public.residents r on r.id = ur2.resident_id where r.phone = '905320001003' and ur2.unit_id = d1;
  begin
    perform public.end_residency(ur);
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: danışma erişimi kapattı';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  perform public.end_residency(ur);
  reset role; select count(*) into n from public.audit_log where site_id = s_a and entity = 'unit_residents'; set local role authenticated;
  if n >= 4 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: işlem geçmişi eksik (%s)', n); end if;
  perform set_config('request.jwt.claims', json_build_object('sub', u_s1, 'role', 'authenticated')::text, true);
  j := public.my_context();
  if jsonb_array_length(j -> 'units') = 1 and j -> 'units' -> 0 ->> 'label' = 'A-2' then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: taşınma sonrası erişim kapanmadı: %s', j); end if;

  -- Sistem yöneticisi yönetici davet eder; davet edilen kabul edince yönetici olur
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role', 'authenticated')::text, true);
  select * into inv from public.create_invite(s_b, 'yonetici', 'B Yöneticisi', '905320001005');
  perform set_config('request.jwt.claims', json_build_object('sub', u_yab, 'role', 'authenticated')::text, true);
  perform public.accept_invite(inv.token);
  j := public.my_context();
  if j -> 'staff' -> 0 ->> 'role' = 'yonetici' and (j -> 'staff' -> 0 ->> 'site_id')::uuid = s_b then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: yönetici daveti işlemedi: %s', j); end if;
  -- Yeni B yöneticisi A sitesinin bloklarını, dairelerini, sakinlerini göremez
  select count(*) into n from public.units where site_id = s_a; if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: B yöneticisi A dairelerini görüyor'; end if;
  select count(*) into n from public.unit_residents where site_id = s_a; if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: B yöneticisi A sakin bağlantılarını görüyor'; end if;
  reset role;

  raise exception 'SONUÇ: % test geçti, % test kaldı.%', gecti, kaldi,
    case when kaldi = 0 then ' Her şey yolunda.' else rapor end;
end;
$$;
