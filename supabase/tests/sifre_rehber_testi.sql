-- Şifre yenileme ve sakin rehberi testi: davetle sakin rehbere eklenir, kabulde aynı kayda bağlanır; yönetici bilgiyi düzeltir
-- (hesabı olanın telefonu değişmez); şifre kodunu kim açabilir (başka sitedeki hesabı ele geçirme yok), kod davet gibi kullanılamaz,
-- yönetici başkasının açtığı şifre kodunu göremez; my_context sitenin türünü verir. Sonunda HER ŞEY GERİ ALINIR.
-- Beklenen: "SONUÇ: 14 test geçti, 0 test kaldı. Her şey yolunda."
do $$
declare
  u_adm uuid := gen_random_uuid(); u_yon uuid := gen_random_uuid(); u_yon2 uuid := gen_random_uuid(); u_dan uuid := gen_random_uuid();
  u_sak uuid := gen_random_uuid(); u_cok uuid := gen_random_uuid(); u_dis uuid := gen_random_uuid();
  s uuid; s2 uuid; blk uuid; d1 uuid; d2 uuid; blk2 uuid; e1 uuid; r uuid; n int; inv record; j jsonb; code text;
  gecti int := 0; kaldi int := 0; rapor text := '';
begin
  insert into auth.users (id, email) values
    (u_adm, 'sr-adm@example.com'), (u_yon, public.login_email('905320008001')), (u_yon2, public.login_email('905320008002')),
    (u_dan, public.login_email('905320008003')), (u_sak, public.login_email('905320008004')), (u_cok, public.login_email('905320008005')),
    (u_dis, public.login_email('905320008006'));
  insert into public.platform_admins (user_id) values (u_adm);
  insert into public.sites (name, type) values ('SR Villa', 'villa') returning id into s;
  insert into public.sites (name, type) values ('SR Diğer', 'apartman') returning id into s2;
  insert into public.memberships (user_id, site_id, role) values (u_yon, s, 'yonetici'), (u_yon2, s, 'yonetici'), (u_dan, s, 'danisma'), (u_dis, s2, 'yonetici');
  insert into public.blocks (site_id, name) values (s, 'A') returning id into blk;
  insert into public.units (site_id, block_id, no, type) values (s, blk, '1', 'villa') returning id into d1;
  insert into public.units (site_id, block_id, no, type) values (s, blk, '2', 'villa') returning id into d2;
  insert into public.blocks (site_id, name) values (s2, 'B') returning id into blk2;
  insert into public.units (site_id, block_id, no) values (s2, blk2, '1') returning id into e1;
  -- u_cok: iki sitede sakin
  insert into public.residents (site_id, full_name, phone, user_id) values (s, 'Çok Siteli', '905320008005', u_cok) returning id into r;
  insert into public.unit_residents (site_id, unit_id, resident_id) values (s, d2, r);
  insert into public.residents (site_id, full_name, phone, user_id) values (s2, 'Çok Siteli', '905320008005', u_cok) returning id into r;
  insert into public.unit_residents (site_id, unit_id, resident_id) values (s2, e1, r);

  set local role authenticated;
  -- 1-2: davet açılınca sakin rehberde (uygulamada değil), danışma görür
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  select * into inv from public.create_invite(s, 'sakin', 'Rehber Sakin', '905320008004', d1, 'kiraci');
  select count(*) into n from public.residents r2 join public.unit_residents ur on ur.resident_id = r2.id and ur.ended_on is null
  where r2.site_id = s and r2.phone = '905320008004' and r2.user_id is null and ur.unit_id = d1 and ur.relation = 'kiraci';
  if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: davetle sakin rehbere eklenmedi'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  select count(*) into n from public.residents where site_id = s and phone = '905320008004';
  if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: danışma uygulamasız sakini görmüyor'; end if;

  -- 3: yönetici bilgiyi düzeltir (hesap yokken telefon da); danışma düzeltemez
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  select id into r from public.residents where site_id = s and phone = '905320008004';
  perform public.update_resident(r, 'Rehber Sakin Düzeltildi', '905320008004');
  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  begin
    perform public.update_resident(r, 'Danışma Değiştirdi', '905320008004');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: danışma sakin bilgisini değiştirdi';
  exception when insufficient_privilege then
    if (select full_name from public.residents where id = r) = 'Rehber Sakin Düzeltildi' then gecti := gecti + 1;
    else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: yönetici adı düzeltemedi'; end if;
  end;

  -- 4: kabulde aynı kayıt hesaba bağlanır (ikinci kayıt yok)
  perform set_config('request.jwt.claims', json_build_object('sub', u_sak, 'role', 'authenticated')::text, true);
  perform public.accept_invite(inv.code);
  select count(*) into n from public.residents where site_id = s and phone = '905320008004' and user_id = u_sak;
  if n = 1 and (select count(*) from public.unit_residents where resident_id = r and ended_on is null) = 1 then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: kabulde sakin kaydı ikilendi'; end if;

  -- 5: hesabı olanın telefonu değiştirilemez
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  begin
    perform public.update_resident(r, 'Rehber Sakin', '905320008099');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: hesabı olanın telefonu değişti';
  exception when sqlstate 'SD020' then gecti := gecti + 1;
  end;

  -- 6-7: yönetici sakine şifre kodu açar; kod davet gibi kullanılamaz
  select c.code into code from public.create_password_reset(s, '905320008004') c;
  j := public.invite_preview(code);
  if j ->> 'role' = 'sifre' and (j ->> 'has_account')::boolean and (j ->> 'valid')::boolean then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: şifre kodu önizlemesi yanlış: %s', j); end if;
  perform set_config('request.jwt.claims', json_build_object('sub', u_sak, 'role', 'authenticated')::text, true);
  begin
    perform public.accept_invite(code);
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: şifre kodu davet olarak kullanıldı';
  exception when sqlstate '22023' then gecti := gecti + 1;
  end;

  -- 8: başka sitede de kayıtlı kişinin kodunu sadece sistem yöneticisi açar
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  begin
    perform public.create_password_reset(s, '905320008005');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: yönetici başka sitedeki hesabın şifresini yeniledi';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;

  -- 9: yönetici başka yöneticinin, danışma kimsenin, başka site yöneticisi bu sitenin kodunu açamaz
  n := 0;
  begin perform public.create_password_reset(s, '905320008002'); exception when insufficient_privilege then n := n + 1; end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  begin perform public.create_password_reset(s, '905320008004'); exception when insufficient_privilege then n := n + 1; end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_dis, 'role', 'authenticated')::text, true);
  begin perform public.create_password_reset(s, '905320008004'); exception when insufficient_privilege then n := n + 1; end;
  if n = 3 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: yetkisiz şifre kodu açıldı (%s/3 engellendi)', n); end if;

  -- 10: hesabı olmayan numaraya kod açılmaz
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  begin
    perform public.create_password_reset(s, '905320008077');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: hesapsız numaraya şifre kodu açıldı';
  exception when sqlstate '22023' then gecti := gecti + 1;
  end;

  -- 11-12: sistem yöneticisi yöneticinin ve çok siteli kişinin kodunu açar; site yöneticisi bu kodları göremez
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role', 'authenticated')::text, true);
  perform public.create_password_reset(s, '905320008002');
  perform public.create_password_reset(s, '905320008005');
  gecti := gecti + 1;
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  select count(*) into n from public.invites where role = 'sifre';
  if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: yönetici %s şifre kodu görüyor (sadece kendi açtığı: 1)', n); end if;

  -- 13: danışma davetleri hiç göremez
  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  select count(*) into n from public.invites;
  if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: danışma davetleri görüyor'; end if;

  -- 14: my_context sitenin türünü verir
  perform set_config('request.jwt.claims', json_build_object('sub', u_sak, 'role', 'authenticated')::text, true);
  j := public.my_context();
  if j -> 'units' -> 0 ->> 'site_type' = 'villa' then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: site türü yok: %s', j); end if;
  reset role;

  raise exception 'SONUÇ: % test geçti, % test kaldı.%', gecti, kaldi,
    case when kaldi = 0 then ' Her şey yolunda.' else rapor end;
end;
$$;
