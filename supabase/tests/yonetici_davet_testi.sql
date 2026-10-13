-- Yönetici yönetici ekler testi: yönetici kendi sitesine yönetici davet eder, davet kabul edilince ikinci yönetici olur;
-- yönetici diğer yöneticinin erişimini kapatabilir, kendisininkini kapatamaz; danışma yönetici davet edemez;
-- yönetici diğer yöneticinin şifresini yenileyemez. Sonunda HER ŞEY GERİ ALINIR.
-- Beklenen: "SONUÇ: 6 test geçti, 0 test kaldı. Her şey yolunda."
do $$
declare
  u_yon uuid := gen_random_uuid(); u_yon2 uuid := gen_random_uuid(); u_dan uuid := gen_random_uuid();
  s uuid; inv record; n int; m uuid;
  gecti int := 0; kaldi int := 0; rapor text := '';
begin
  insert into auth.users (id, email) values (u_yon, public.login_email('905320002001')), (u_yon2, public.login_email('905320002002')), (u_dan, 'yd-dan@example.com');
  insert into public.sites (name, type) values ('YD Site', 'apartman') returning id into s;
  insert into public.memberships (user_id, site_id, role) values (u_yon, s, 'yonetici'), (u_dan, s, 'danisma');

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  select * into inv from public.create_invite(s, 'yonetici', 'İkinci Yönetici', '905320002002');
  gecti := gecti + 1;
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon2, 'role', 'authenticated')::text, true);
  perform public.accept_invite(inv.code);
  if public.has_site_role(s, '{yonetici}') then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: davet edilen yönetici olmadı'; end if;

  -- Kendi erişimini kapatamaz, diğerininkini kapatır
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  update public.memberships set ended_on = current_date where user_id = u_yon and site_id = s; get diagnostics n = row_count;
  if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: yönetici kendi erişimini kapattı'; end if;
  update public.memberships set ended_on = current_date where user_id = u_yon2 and site_id = s; get diagnostics n = row_count;
  if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: yönetici diğer yöneticinin erişimini kapatamadı'; end if;

  -- Danışma yönetici davet edemez
  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  begin
    perform public.create_invite(s, 'yonetici', 'Danışmanın Adamı', '905320002009');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: danışma yönetici davet etti';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;

  -- Yönetici diğer yöneticinin şifresini yenileyemez (yeniden ekleyip dene)
  reset role; insert into public.memberships (user_id, site_id, role) values (u_yon2, s, 'yonetici'); set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  begin
    perform public.create_password_reset(s, '905320002002');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: yönetici diğer yöneticinin şifresini yeniledi';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;
  reset role;

  raise exception 'SONUÇ: % test geçti, % test kaldı.%', gecti, kaldi,
    case when kaldi = 0 then ' Her şey yolunda.' else rapor end;
end;
$$;
