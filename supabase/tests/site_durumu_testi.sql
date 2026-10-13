-- Site aktif/kapalı testi: kapalı sitede yönetici, danışma ve sakin hiçbir şey göremez/yapamaz; sistem yöneticisi görür;
-- site yeniden açılınca her şey geri gelir; istatistikleri sadece sistem yöneticisi alır. Sonunda HER ŞEYİ GERİ ALIR.
-- Beklenen: "SONUÇ: 14 test geçti, 0 test kaldı. Her şey yolunda."
do $$
declare
  u_adm uuid := gen_random_uuid(); u_yon uuid := gen_random_uuid(); u_dan uuid := gen_random_uuid(); u_sak uuid := gen_random_uuid(); u_yeni uuid := gen_random_uuid();
  s uuid; blk uuid; d uuid; r uuid; t uuid; inv record; n int; j jsonb;
  gecti int := 0; kaldi int := 0; rapor text := '';
begin
  insert into auth.users (id, email) values (u_adm, 'sd-adm@example.com'), (u_yon, 'sd-yon@example.com'), (u_dan, 'sd-dan@example.com'),
    (u_sak, 'sd-sak@example.com'), (u_yeni, public.login_email('905320003009'));
  insert into public.platform_admins (user_id) values (u_adm);
  insert into public.sites (name, type) values ('SD Site', 'apartman') returning id into s;
  insert into public.memberships (user_id, site_id, role) values (u_yon, s, 'yonetici'), (u_dan, s, 'danisma');
  insert into public.blocks (site_id, name) values (s, 'A') returning id into blk;
  insert into public.units (site_id, block_id, no) values (s, blk, '1') returning id into d;
  insert into public.residents (site_id, full_name, phone, user_id) values (s, 'SD Sakin', '905320003001', u_sak) returning id into r;
  insert into public.unit_residents (site_id, unit_id, resident_id) values (s, d, r);

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_sak, 'role', 'authenticated')::text, true);
  t := public.create_ticket(gen_random_uuid(), d, 'ariza', 'daire', 'Kapanmadan önce', null, false);
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  select * into inv from public.create_invite(s, 'sakin', 'Yeni Sakin', '905320003009', d, 'kiraci');

  -- Sistem yöneticisi siteyi kapatır (ödeme kesildi)
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role', 'authenticated')::text, true);
  update public.sites set active = false where id = s;

  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  select count(*) into n from public.tickets where site_id = s; if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: kapalı sitede yönetici kayıt görüyor'; end if;
  select count(*) into n from public.units where site_id = s; if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: kapalı sitede yönetici daire görüyor'; end if;
  j := public.my_context();
  if jsonb_array_length(j -> 'staff') = 0 and j -> 'closed_sites' ? 'SD Site' then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: yönetici rol bilgisi yanlış: %s', j); end if;
  begin
    perform public.set_ticket_status(t, 'yapiliyor');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: kapalı sitede yönetici durum değiştirdi';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  begin
    perform public.create_invite(s, 'sakin', 'Başka', '905320003008', d, 'malik');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: kapalı sitede danışma davet açtı';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', u_sak, 'role', 'authenticated')::text, true);
  select count(*) into n from public.tickets; if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: kapalı sitede sakin kayıt görüyor'; end if;
  begin
    perform public.create_ticket(gen_random_uuid(), d, 'talep', 'daire', 'Kapalıyken', null, false);
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: kapalı sitede sakin kayıt açtı';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;
  j := public.my_context();
  if jsonb_array_length(j -> 'units') = 0 and j -> 'closed_sites' ? 'SD Site' then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: sakin rol bilgisi yanlış: %s', j); end if;

  -- Kapalı sitenin daveti kabul edilemez
  perform set_config('request.jwt.claims', json_build_object('sub', u_yeni, 'role', 'authenticated')::text, true);
  begin
    perform public.accept_invite(inv.code);
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: kapalı sitenin daveti kabul edildi';
  exception when sqlstate '22023' then gecti := gecti + 1;
  end;

  -- İstatistik: sadece sistem yöneticisi
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  begin
    perform * from public.platform_site_stats();
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: yönetici bütün sitelerin istatistiğini aldı';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm, 'role', 'authenticated')::text, true);
  select count(*) into n from public.tickets where site_id = s; if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: sistem yöneticisi kapalı sitenin kaydını görmüyor'; end if;
  select open_tickets into n from public.platform_site_stats() where site_id = s;
  if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: istatistik açık kayıt %s', n); end if;

  -- Site yeniden açılır: her şey geri gelir
  update public.sites set active = true where id = s;
  perform set_config('request.jwt.claims', json_build_object('sub', u_sak, 'role', 'authenticated')::text, true);
  select count(*) into n from public.tickets; if n = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: açılınca sakin kaydını görmüyor'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  perform public.set_ticket_status(t, 'yapiliyor');
  gecti := gecti + 1;
  reset role;

  raise exception 'SONUÇ: % test geçti, % test kaldı.%', gecti, kaldi,
    case when kaldi = 0 then ' Her şey yolunda.' else rapor end;
end;
$$;
