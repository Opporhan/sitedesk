-- Site koduyla katılma testi: sakin kodla daireleri görür ve istek gönderir; yönetici görür, onaylar/reddeder; onayda rehbere ve
-- daireye bağlanır, bildirim gider; yanlış kod, başka sitenin dairesi, tekrar istek; başkası istekleri göremez; kod yenilenince eski kod çalışmaz.
-- Sonunda HER ŞEY GERİ ALINIR. Beklenen: "SONUÇ: 10 test geçti, 0 test kaldı. Her şey yolunda."
do $$
declare
  u_yon uuid := gen_random_uuid(); u_dan uuid := gen_random_uuid(); u_sak uuid := gen_random_uuid(); u_red uuid := gen_random_uuid(); u_dis uuid := gen_random_uuid();
  s uuid; s2 uuid; blk uuid; d1 uuid; d2 uuid; e1 uuid; code text; j jsonb; req uuid; req2 uuid; n int; msg text;
  gecti int := 0; kaldi int := 0; rapor text := '';
begin
  insert into auth.users (id, email) values (u_yon, 'kt-yon@example.com'), (u_dan, 'kt-dan@example.com'),
    (u_sak, public.login_email('905320003001')), (u_red, public.login_email('905320003002')), (u_dis, 'kt-dis@example.com');
  insert into public.push_tokens (token, user_id, platform) values ('ExponentPushToken[kt-yon]', u_yon, 'android'), ('ExponentPushToken[kt-sak]', u_sak, 'android');
  insert into public.sites (name, type) values ('KT Site', 'apartman') returning id, join_code into s, code;
  insert into public.sites (name, type) values ('KT Başka', 'apartman') returning id into s2;
  insert into public.memberships (user_id, site_id, role) values (u_yon, s, 'yonetici'), (u_dan, s, 'danisma'), (u_dis, s2, 'yonetici');
  insert into public.blocks (site_id, name) values (s, 'A') returning id into blk;
  insert into public.units (site_id, block_id, no) values (s, blk, '1') returning id into d1;
  insert into public.units (site_id, block_id, no) values (s, blk, '2') returning id into d2;
  insert into public.blocks (site_id, name) values (s2, 'B') returning id into blk;
  insert into public.units (site_id, block_id, no) values (s2, blk, '1') returning id into e1;

  set local role authenticated;
  -- 1: kodla site ve daireler (küçük harf/boşluk da olur)
  perform set_config('request.jwt.claims', json_build_object('sub', u_sak, 'role', 'authenticated')::text, true);
  j := public.site_by_code(' ' || lower(code) || ' ');
  if j ->> 'name' = 'KT Site' and jsonb_array_length(j -> 'units') = 2 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: kodla site bulunamadı: %s', j); end if;
  -- 2: yanlış kod
  begin
    perform public.request_join('YANLIS', d1, 'KT Sakin', 'malik');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: yanlış kodla istek gitti';
  exception when sqlstate 'SD060' then gecti := gecti + 1;
  end;
  -- 3: başka sitenin dairesi
  begin
    perform public.request_join(code, e1, 'KT Sakin', 'malik');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başka sitenin dairesine istek gitti';
  exception when sqlstate '22023' then gecti := gecti + 1;
  end;
  -- 4: istek + yöneticiye bildirim; tekrar gönderilirse aynı istek
  reset role; select count(*) into n from net.http_request_queue; set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_sak, 'role', 'authenticated')::text, true);
  req := public.request_join(code, d1, 'KT Sakin', 'kiraci');
  req2 := public.request_join(code, d1, 'KT Sakin', 'kiraci');
  reset role;
  select convert_from(q.body, 'utf8') into msg from net.http_request_queue q order by id desc limit 1;
  if req = req2 and msg like '%kt-yon%' and msg like '%Katılma isteği%' then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: istek/bildirim yanlış: %s', msg); end if;
  set local role authenticated;
  -- 5: sakin henüz sitenin hiçbir şeyini görmez, kendi isteğini görür
  perform set_config('request.jwt.claims', json_build_object('sub', u_sak, 'role', 'authenticated')::text, true);
  if (select count(*) from public.units where site_id = s) = 0 and (select count(*) from public.join_requests) = 1
     and jsonb_array_length(public.my_context() -> 'pending_joins') = 1 then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: onaysız sakin siteyi görüyor ya da isteğini görmüyor'; end if;
  -- 6: danışma ve başka site yöneticisi istekleri göremez, onaylayamaz
  n := 0;
  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  if (select count(*) from public.join_requests) = 0 then n := n + 1; end if;
  begin perform public.decide_join(req, true); exception when insufficient_privilege then n := n + 1; end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_dis, 'role', 'authenticated')::text, true);
  begin perform public.decide_join(req, true); exception when insufficient_privilege then n := n + 1; end;
  if n = 3 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: yetkisiz kişi isteği gördü/onayladı (%s/3)', n); end if;
  -- 7: yönetici onaylar → sakin daireye kiracı olarak bağlanır, rehberde tek kayıt, bildirim
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  if (select count(*) from public.join_requests where site_id = s and status = 'bekliyor') <> 1 then kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: yönetici isteği görmüyor'; end if;
  perform public.decide_join(req, true);
  reset role;
  select convert_from(q.body, 'utf8') into msg from net.http_request_queue q order by id desc limit 1;
  if exists (select 1 from public.residents r join public.unit_residents ur on ur.resident_id = r.id and ur.ended_on is null
             where r.user_id = u_sak and ur.unit_id = d1 and ur.relation = 'kiraci') and msg like '%kt-sak%' and msg like '%Siteye katıldınız%' then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: onay sonrası bağlantı/bildirim yok: %s', msg); end if;
  set local role authenticated;
  -- 8: onaylanan sakin artık dairesini görür
  perform set_config('request.jwt.claims', json_build_object('sub', u_sak, 'role', 'authenticated')::text, true);
  if (select count(*) from public.units where id = d1) = 1 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: onaylanan sakin dairesini görmüyor'; end if;
  -- 9: ret → bağlanmaz
  perform set_config('request.jwt.claims', json_build_object('sub', u_red, 'role', 'authenticated')::text, true);
  req := public.request_join(code, d2, 'KT Reddedilen', 'malik');
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  perform public.decide_join(req, false);
  perform set_config('request.jwt.claims', json_build_object('sub', u_red, 'role', 'authenticated')::text, true);
  if (select count(*) from public.units) = 0 and (select status from public.join_requests where id = req) = 'reddedildi' then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: reddedilen kişi daireyi görüyor'; end if;
  -- 10: kod yenilenince eski kod çalışmaz (danışma yenileyemez)
  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  n := 0;
  begin perform public.renew_join_code(s); exception when insufficient_privilege then n := n + 1; end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  perform public.renew_join_code(s);
  perform set_config('request.jwt.claims', json_build_object('sub', u_red, 'role', 'authenticated')::text, true);
  if n = 1 and public.site_by_code(code) is null then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: eski kod hâlâ çalışıyor ya da danışma kodu yeniledi'; end if;
  reset role;

  raise exception 'SONUÇ: % test geçti, % test kaldı.%', gecti, kaldi,
    case when kaldi = 0 then ' Her şey yolunda.' else rapor end;
end;
$$;
