-- Temel yetki testi (sıfırdan sonraki sade yapı): sistem yöneticisi her şeyi yönetir; yönetici ve danışma sadece kendi sitesini
-- ve o sitenin sakinlerini görür, hiçbir şey ekleyemez; sakin sadece kendi kaydını ve sitesini görür; başka sitedeki kimse göremez.
-- Sonunda HER ŞEYİ GERİ ALIR. Beklenen: "SONUÇ: 13 test geçti, 0 test kaldı. Her şey yolunda."
do $$
declare
  u_adm uuid := gen_random_uuid(); u_yon uuid := gen_random_uuid(); u_dan uuid := gen_random_uuid();
  u_sak uuid := gen_random_uuid(); u_dis uuid := gen_random_uuid();
  s_a uuid; s_b uuid; r_a uuid; r_b uuid; blk uuid; unit uuid; n int;
  gecti int := 0; kaldi int := 0; rapor text := '';
begin
  insert into auth.users (id, email) values (u_adm, 'tt-adm@example.com'), (u_yon, 'tt-yon@example.com'), (u_dan, 'tt-dan@example.com'),
    (u_sak, public.login_email('905320000999')), (u_dis, 'tt-dis@example.com');
  insert into public.platform_admins (user_id) values (u_adm);
  insert into public.sites (name, type) values ('TT A', 'villa') returning id into s_a;
  insert into public.sites (name, type) values ('TT B', 'apartman') returning id into s_b;
  insert into public.memberships (user_id, site_id, role) values (u_yon, s_a, 'yonetici'), (u_dan, s_a, 'danisma'), (u_dis, s_b, 'yonetici');
  insert into public.residents (site_id, full_name, phone, user_id) values (s_a, 'Sakin A', '905320000999', u_sak) returning id into r_a;
  insert into public.residents (site_id, full_name, phone) values (s_b, 'Sakin B', '905320000998') returning id into r_b;
  -- Sakin A bir dairede oturuyor (sakin, sadece oturduğu sürece sitesini görür)
  insert into public.blocks (site_id, name) values (s_a, 'A') returning id into blk;
  insert into public.units (site_id, block_id, no) values (s_a, blk, '1') returning id into unit;
  insert into public.unit_residents (site_id, unit_id, resident_id) values (s_a, unit, r_a);

  -- Eski rol kabul edilmez
  begin
    insert into public.memberships (user_id, site_id, role) values (u_dis, s_a, 'izleyici');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: izleyici rolü eklenebildi';
  exception when check_violation then gecti := gecti + 1;
  end;

  set local role authenticated;

  -- Yönetici: kendi sitesi ve sakinleri; başka site yok; ekleyemez
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  select count(*) into n from public.sites; if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: yönetici %s site görüyor', n); end if;
  select count(*) into n from public.residents; if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: yönetici %s sakin görüyor', n); end if;
  begin
    insert into public.residents (site_id, full_name) values (s_a, 'Yeni');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: yönetici sakin ekledi';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;
  begin
    insert into public.memberships (user_id, site_id, role) values (u_dis, s_a, 'danisma');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: yönetici üyelik ekledi';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;
  -- Danışma: kendi sitesi ve sakinleri
  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  select count(*) into n from public.residents; if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: danışma %s sakin görüyor', n); end if;

  -- Sakin: kendi kaydı ve sitesi
  perform set_config('request.jwt.claims', json_build_object('sub', u_sak, 'role', 'authenticated')::text, true);
  select count(*) into n from public.residents; if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: sakin %s sakin kaydı görüyor', n); end if;
  select count(*) into n from public.sites where id = s_a; if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: sakin kendi sitesini görmüyor'; end if;

  -- Başka sitenin yöneticisi A sitesini ve sakinini göremez
  perform set_config('request.jwt.claims', json_build_object('sub', u_dis, 'role', 'authenticated')::text, true);
  select count(*) into n from public.sites where id = s_a; if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başka site yöneticisi A sitesini görüyor'; end if;
  select count(*) into n from public.residents where id = r_a; if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başka site yöneticisi A sakinini görüyor'; end if;

  -- Sistem yöneticisi: hepsini görür, site ekler (sakin ve görevli sadece davetle eklenir)
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role', 'authenticated')::text, true);
  select count(*) into n from public.sites where id in (s_a, s_b); if n = 2 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: sistem yöneticisi siteleri görmüyor'; end if;
  insert into public.sites (name, type) values ('Yeni Site', 'villa');
  gecti := gecti + 1;

  -- Girişsiz kişi hiçbir şey göremez
  reset role;
  set local role anon;
  begin
    select count(*) into n from public.sites;
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: girişsiz kişi siteleri okuyabiliyor';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;
  reset role;

  raise exception 'SONUÇ: % test geçti, % test kaldı.%', gecti, kaldi,
    case when kaldi = 0 then ' Her şey yolunda.' else rapor end;
end;
$$;
