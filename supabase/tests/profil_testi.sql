-- Profil resmi ve davet yetkisi testi: danışma davet edemez; kişi sadece kendi klasörüne resim yükler; resmi ve profili
-- kendisi, aynı sitedekiler ve sistem yöneticisi görür; başka sitedeki göremez. Sonunda HER ŞEYİ GERİ ALIR.
-- Beklenen: "SONUÇ: 10 test geçti, 0 test kaldı. Her şey yolunda."
do $$
declare
  u_yon uuid := gen_random_uuid(); u_dan uuid := gen_random_uuid(); u_sak uuid := gen_random_uuid(); u_dis uuid := gen_random_uuid();
  s_a uuid; s_b uuid; blk uuid; d uuid; r uuid; n int; p text;
  gecti int := 0; kaldi int := 0; rapor text := '';
begin
  insert into auth.users (id, email) values (u_yon, 'pr-yon@example.com'), (u_dan, 'pr-dan@example.com'), (u_sak, 'pr-sak@example.com'), (u_dis, 'pr-dis@example.com');
  insert into public.sites (name, type) values ('PR A', 'apartman') returning id into s_a;
  insert into public.sites (name, type) values ('PR B', 'apartman') returning id into s_b;
  insert into public.memberships (user_id, site_id, role) values (u_yon, s_a, 'yonetici'), (u_dan, s_a, 'danisma'), (u_dis, s_b, 'yonetici');
  insert into public.blocks (site_id, name) values (s_a, 'A') returning id into blk;
  insert into public.units (site_id, block_id, no) values (s_a, blk, '1') returning id into d;
  insert into public.residents (site_id, full_name, phone, user_id) values (s_a, 'PR Sakin', '905320004001', u_sak) returning id into r;
  insert into public.unit_residents (site_id, unit_id, resident_id) values (s_a, d, r);
  p := u_sak || '/resim.jpg';
  insert into storage.objects (bucket_id, name, owner) values ('profil', p, u_sak);

  set local role authenticated;
  -- Danışma artık davet edemez; yönetici eder
  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  begin
    perform public.create_invite(s_a, 'sakin', 'Yeni Sakin', '905320004009', d, 'malik');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: danışma sakin davet etti';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;
  select count(*) into n from public.invites; if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: danışma davetleri görüyor'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  perform public.create_invite(s_a, 'sakin', 'Yeni Sakin', '905320004009', d, 'malik');
  gecti := gecti + 1;

  -- Sakin kendi resmini kaydeder; başkasının klasörüne yazamaz
  perform set_config('request.jwt.claims', json_build_object('sub', u_sak, 'role', 'authenticated')::text, true);
  perform public.set_my_avatar(p);
  if (select avatar_path from public.profiles where user_id = u_sak) = p then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: resim kaydedilmedi'; end if;
  begin
    perform public.set_my_avatar(u_yon || '/baskasi.jpg');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başkasının yolu kabul edildi';
  exception when sqlstate '22023' then gecti := gecti + 1;
  end;
  begin
    insert into storage.objects (bucket_id, name) values ('profil', u_yon || '/sizma.jpg');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başkasının klasörüne yüklendi';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;

  -- Aynı sitedeki yönetici ve danışma sakinin profilini ve resmini görür; başka sitenin yöneticisi göremez
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  select count(*) into n from public.profiles where user_id = u_sak; if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: yönetici sakinin profilini görmüyor'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  select count(*) into n from storage.objects where bucket_id = 'profil' and name = p; if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: danışma sakinin resmini görmüyor'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', u_dis, 'role', 'authenticated')::text, true);
  select count(*) into n from public.profiles where user_id = u_sak; if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başka site yöneticisi profili görüyor'; end if;
  select count(*) into n from storage.objects where bucket_id = 'profil' and name = p; if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başka site yöneticisi resmi görüyor'; end if;
  reset role;

  raise exception 'SONUÇ: % test geçti, % test kaldı.%', gecti, kaldi,
    case when kaldi = 0 then ' Her şey yolunda.' else rapor end;
end;
$$;
