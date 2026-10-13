-- Site açma testi: yönetici yeni site açar ve o sitenin yöneticisi olur (süresiz, sistem yöneticisine bildirim);
-- kayıtlı her kullanıcı kendi sitesini açar (günde 3), girişsiz açamaz; sistem yöneticisi açar (üye olmaz). Sonunda HER ŞEY GERİ ALINIR.
-- Beklenen: "SONUÇ: 6 test geçti, 0 test kaldı. Her şey yolunda."
do $$
declare
  u_adm uuid := gen_random_uuid(); u_yon uuid := gen_random_uuid(); u_dan uuid := gen_random_uuid(); u_r uuid := gen_random_uuid();
  s uuid; yeni uuid; n int; msg text;
  gecti int := 0; kaldi int := 0; rapor text := '';
begin
  insert into auth.users (id, email) values (u_adm, 'sa-adm@example.com'), (u_yon, 'sa-yon@example.com'), (u_dan, 'sa-dan@example.com'), (u_r, 'sa-r@example.com');
  insert into public.platform_admins (user_id) values (u_adm);
  insert into public.push_tokens (token, user_id, platform) values ('ExponentPushToken[sa-admin]', u_adm, 'android');
  insert into public.sites (name, type) values ('SA Site', 'apartman') returning id into s;
  insert into public.memberships (user_id, site_id, role) values (u_yon, s, 'yonetici'), (u_dan, s, 'danisma');

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  yeni := public.create_site('SA Yeni Site', 'villa', 'Bodrum');
  if exists (select 1 from public.memberships where user_id = u_yon and site_id = yeni and role = 'yonetici' and ended_on is null)
     then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: açan yönetici üye olmadı '; end if;
  reset role;
  select convert_from(q.body, 'utf8') into msg from net.http_request_queue q order by id desc limit 1;
  if msg like '%sa-admin%' and msg like '%Yeni site açıldı%' then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: sistem yöneticisine bildirim gitmedi: %s', msg); end if;

  -- Kayıtlı her kullanıcı (danışma, rolsüz, kapalı sitenin yöneticisi) kendi sitesini açabilir ve yöneticisi olur; girişsiz açamaz; günde en fazla 3
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_r, 'role', 'authenticated')::text, true);
  yeni := public.create_site('Rolsüzün Sitesi', 'apartman');
  if exists (select 1 from public.memberships where user_id = u_r and site_id = yeni and role = 'yonetici') and (select join_code from public.sites where id = yeni) ~ '^[A-Z2-9]{6}$' then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: rolsüz kullanıcı site açıp yöneticisi olamadı ya da site kodu yok'; end if;
  perform public.create_site('İkinci', 'apartman');
  perform public.create_site('Üçüncü', 'apartman');
  begin
    perform public.create_site('Dördüncü', 'apartman');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: günde 3 site sınırı çalışmadı';
  exception when sqlstate 'SD050' then gecti := gecti + 1;
  end;
  reset role;
  set local role anon;
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  begin
    perform public.create_site('Girişsiz', 'apartman');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: girişsiz site açtı';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;
  reset role;
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role', 'authenticated')::text, true);
  yeni := public.create_site('SA Sistem Sitesi', 'apartman');
  if not exists (select 1 from public.memberships where site_id = yeni) then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: sistem yöneticisinin açtığı site yanlış'; end if;
  reset role;

  raise exception 'SONUÇ: % test geçti, % test kaldı.%', gecti, kaldi,
    case when kaldi = 0 then ' Her şey yolunda.' else rapor end;
end;
$$;
