-- Güvenlik denetimi testi (adım 8): her tablo, fonksiyon ve dosya deposu için farklı saldıranlar denenir.
-- Saldıranlar: başka sitenin yöneticisi / danışması / sakini, rolsüz hesap, taşınmış sakin, girişsiz (anon);
-- ayrıca sitenin kendi danışması ve başka dairenin sakini (para/kişi bilgisi, başkasının kaydı).
-- Genel kurallar veritabanından okunur: YENİ TABLO EKLENİNCE bu test kendiliğinden kapsar
-- (o tabloya burada bir "kurban" satırı eklenmezse ya da izinler listede yoksa test KALIR).
-- Sonunda HER ŞEY GERİ ALINIR. Beklenen: "SONUÇ: 38 test geçti, 0 test kaldı. Her şey yolunda."
do $$
declare
  u_p uuid := gen_random_uuid();  -- sistem yöneticisi
  u_y uuid := gen_random_uuid();  -- S yöneticisi
  u_d uuid := gen_random_uuid();  -- S danışması
  u_a uuid := gen_random_uuid();  -- S sakini, A-1 malik
  u_a2 uuid := gen_random_uuid(); -- S sakini, A-1 kiracı (aynı daire)
  u_b uuid := gen_random_uuid();  -- S sakini, A-2 (başka daire)
  u_m uuid := gen_random_uuid();  -- S'den taşınmış sakin
  u_y2 uuid := gen_random_uuid(); -- T yöneticisi
  u_d2 uuid := gen_random_uuid(); -- T danışması
  u_c uuid := gen_random_uuid();  -- T sakini
  u_r uuid := gen_random_uuid();  -- rolsüz hesap
  s uuid; t_site uuid; blk uuid; blk_t uuid; d1 uuid; d2 uuid; dt uuid; r uuid; ur_a uuid;
  t1 uuid; t2 uuid; pk uuid; vi uuid; inv uuid; tbl text; q text; n int; bad text;
  attacker uuid; attackers uuid[]; names text[] := array['başka site yöneticisi', 'başka site danışması', 'başka site sakini', 'rolsüz hesap', 'taşınmış sakin'];
  site_tables text[];
  gecti int := 0; kaldi int := 0; rapor text := '';
begin
  insert into auth.users (id, email) values
    (u_p, 'gt-p@example.com'), (u_y, 'gt-y@example.com'), (u_d, 'gt-d@example.com'), (u_a, 'gt-a@example.com'), (u_a2, 'gt-a2@example.com'),
    (u_b, 'gt-b@example.com'), (u_m, 'gt-m@example.com'), (u_y2, 'gt-y2@example.com'), (u_d2, 'gt-d2@example.com'), (u_c, 'gt-c@example.com'), (u_r, 'gt-r@example.com');
  update public.profiles set phone = '90532000' || right(replace(user_id::text, '-', ''), 4) where user_id in (u_y, u_d, u_a, u_b);
  insert into public.platform_admins (user_id) values (u_p);
  insert into public.sites (name, type) values ('GT Site', 'apartman') returning id into s;
  insert into public.sites (name, type) values ('GT Diğer', 'apartman') returning id into t_site;
  insert into public.memberships (user_id, site_id, role) values (u_y, s, 'yonetici'), (u_d, s, 'danisma'), (u_y2, t_site, 'yonetici'), (u_d2, t_site, 'danisma');
  insert into public.blocks (site_id, name) values (s, 'A') returning id into blk;
  insert into public.blocks (site_id, name) values (t_site, 'A') returning id into blk_t;
  insert into public.units (site_id, block_id, no) values (s, blk, '1') returning id into d1;
  insert into public.units (site_id, block_id, no) values (s, blk, '2') returning id into d2;
  insert into public.units (site_id, block_id, no) values (t_site, blk_t, '1') returning id into dt;
  insert into public.residents (site_id, full_name, phone, user_id) values (s, 'GT Malik', '905320007001', u_a) returning id into r;
  insert into public.unit_residents (site_id, unit_id, resident_id, relation) values (s, d1, r, 'malik') returning id into ur_a;
  insert into public.residents (site_id, full_name, phone, user_id) values (s, 'GT Kiracı', '905320007002', u_a2) returning id into r;
  insert into public.unit_residents (site_id, unit_id, resident_id, relation) values (s, d1, r, 'kiraci');
  insert into public.residents (site_id, full_name, phone, user_id) values (s, 'GT Komşu', '905320007003', u_b) returning id into r;
  insert into public.unit_residents (site_id, unit_id, resident_id, relation) values (s, d2, r, 'malik');
  insert into public.residents (site_id, full_name, phone, user_id) values (s, 'GT Taşınan', '905320007004', u_m) returning id into r;
  insert into public.unit_residents (site_id, unit_id, resident_id, relation, started_on, ended_on) values (s, d1, r, 'malik', current_date - 400, current_date - 10);
  insert into public.residents (site_id, full_name, phone, user_id) values (t_site, 'GT Başka', '905320007005', u_c) returning id into r;
  insert into public.unit_residents (site_id, unit_id, resident_id, relation) values (t_site, dt, r, 'malik');

  -- Kurban satırları (sitenin gerçek kullanıcıları kendi fonksiyonlarıyla)
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_y, 'role', 'authenticated')::text, true);
  perform public.create_invite(s, 'sakin', 'GT Davetli', '905320007099', d2, 'kiraci');
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
  t1 := public.create_ticket(gen_random_uuid(), d1, 'ariza', 'daire', 'Musluk akıyor', null, false);
  perform public.register_push_token('ExponentPushToken[gt-a]', 'android');
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
  t2 := public.create_ticket(gen_random_uuid(), d2, 'talep', 'daire', 'Kapı ayarı', null, false);
  perform public.register_push_token('ExponentPushToken[gt-b]', 'android');
  perform set_config('request.jwt.claims', json_build_object('sub', u_y, 'role', 'authenticated')::text, true);
  perform public.add_ticket_note(t1, 'Bakılacak');
  perform set_config('request.jwt.claims', json_build_object('sub', u_d, 'role', 'authenticated')::text, true);
  pk := public.record_package(gen_random_uuid(), d1, null);
  vi := public.record_visitor(gen_random_uuid(), d1, 'GT Misafir', null);
  reset role;
  insert into public.join_requests (site_id, unit_id, user_id, full_name, phone, relation) values (s, d1, u_b, 'GT İstek', '905320007088', 'malik');
  select id into inv from public.invites where site_id = s limit 1;
  insert into storage.objects (bucket_id, name, metadata) values ('kayitlar', s || '/' || t1 || '/a.jpg', '{"mimetype": "image/jpeg", "size": 1000}');
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
  perform public.add_ticket_media(t1, s || '/' || t1 || '/a.jpg', 'foto', 1000, null);
  reset role;

  -- G1–G7: veritabanının genel kuralları (yeni tablo/fonksiyon da kapsanır)
  select string_agg(c.relname, ', ') into bad from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p') and not c.relrowsecurity;
  if bad is null then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: satır güvenliği (RLS) kapalı tablo: ' || bad; end if;

  select string_agg(c.relname, ', ') into bad from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p', 'v', 'm')
    and (has_table_privilege('anon', c.oid, 'SELECT') or has_any_column_privilege('anon', c.oid, 'INSERT') or has_any_column_privilege('anon', c.oid, 'UPDATE') or has_table_privilege('anon', c.oid, 'DELETE'));
  if bad is null then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: girişsiz erişilebilen tablo: ' || bad; end if;

  -- Uygulamanın doğrudan yazabildiği yerler sadece bunlar (gerisi fonksiyonla); yeni bir izin bilerek buraya eklenmeli
  select string_agg(x, ', ') into bad from (
    select c.relname || ':' || p.priv as x
    from pg_class c cross join (values ('INSERT'), ('UPDATE'), ('DELETE')) p(priv)
    where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p', 'v')
      and case p.priv when 'DELETE' then has_table_privilege('authenticated', c.oid, 'DELETE') else has_any_column_privilege('authenticated', c.oid, p.priv) end
    except select unnest(array['blocks:INSERT', 'blocks:UPDATE', 'blocks:DELETE', 'units:INSERT', 'units:UPDATE', 'units:DELETE',
                               'sites:INSERT', 'sites:UPDATE', 'memberships:UPDATE', 'profiles:UPDATE', 'push_tokens:DELETE'])) z;
  if bad is null then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: beklenmeyen yazma izni: ' || bad; end if;

  select string_agg(p.proname, ', ') into bad from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef
    and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
  if bad is null then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: search_path sabit olmayan yetkili fonksiyon: ' || bad; end if;

  select string_agg(p.proname, ', ') into bad from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef
    and p.prorettype <> 'trigger'::regtype and has_function_privilege('anon', p.oid, 'EXECUTE') and p.proname <> 'invite_preview';
  if bad is null then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: girişsiz çağrılabilen fonksiyon: ' || bad; end if;

  select string_agg(f, ', ') into bad from unnest(array['notify_users', 'files_to_purge', 'mark_media_deleted', 'health_report', 'purge_old_visitors',
      'site_manager_users', 'unit_resident_users', 'unit_label', 'user_site_ids', 'find_user_id_by_email', 'allow_signup']) f
    where exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = f and has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  if bad is null then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: uygulamanın çağırabildiği sunucu fonksiyonu: ' || bad; end if;

  select array_agg(c.relname::text order by c.relname) into site_tables from pg_class c
  where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
    and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'site_id' and not a.attisdropped) or c.relname = 'sites' and c.relnamespace = 'public'::regnamespace;
  bad := null;
  foreach tbl in array site_tables loop
    execute format('select count(*) from public.%I where %s = $1', tbl, case when tbl = 'sites' then 'id' else 'site_id' end) into n using s;
    if n = 0 then bad := concat_ws(', ', bad, tbl); end if;
  end loop;
  if bad is null then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: testte kurban satırı olmayan tablo (teste ekleyin): ' || bad; end if;

  -- O1–O5: dışarıdakiler sitenin HİÇBİR satırını göremez (taşınmış sakin kendi rehber kaydını görebilir)
  attackers := array[u_y2, u_d2, u_c, u_r, u_m];
  for i in 1 .. array_length(attackers, 1) loop
    attacker := attackers[i];
    bad := null;
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', attacker, 'role', 'authenticated')::text, true);
    foreach tbl in array site_tables loop
      continue when attacker = u_m and tbl in ('residents', 'unit_residents');
      continue when tbl = 'audit_log'; -- uygulama işlem geçmişini hiç okuyamaz (denetim_testi)
      execute format('select count(*) from public.%I where %s = $1', tbl, case when tbl = 'sites' then 'id' else 'site_id' end) into n using s;
      if n > 0 then bad := concat_ws(', ', bad, tbl || '=' || n); end if;
    end loop;
    select count(*) into n from storage.objects where bucket_id = 'kayitlar' and name like s || '/%';
    if n > 0 then bad := concat_ws(', ', bad, 'kayıt dosyası'); end if;
    reset role;
    if bad is null then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: %s görüyor: %s', names[i], bad); end if;
  end loop;

  -- I1–I3: sitenin içindekiler sadece kendi payını görür
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_d, 'role', 'authenticated')::text, true);
  select count(*) from public.invites where site_id = s into n;
  if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: danışma davetleri veya işlem geçmişini görüyor'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
  bad := null;
  if (select count(*) from public.tickets where id = t1) > 0 then bad := concat_ws(', ', bad, 'komşunun kaydı'); end if;
  if (select count(*) from public.ticket_events where ticket_id = t1) > 0 then bad := concat_ws(', ', bad, 'komşunun kayıt geçmişi'); end if;
  if (select count(*) from public.ticket_media where ticket_id = t1) > 0 then bad := concat_ws(', ', bad, 'komşunun dosyası'); end if;
  if (select count(*) from storage.objects where bucket_id = 'kayitlar' and name like s || '/' || t1 || '/%') > 0 then bad := concat_ws(', ', bad, 'komşunun depo dosyası'); end if;
  if (select count(*) from public.packages where id = pk) + (select count(*) from public.visitors where id = vi) > 0 then bad := concat_ws(', ', bad, 'komşunun kargo/ziyaretçisi'); end if;
  if (select count(*) from public.units where site_id = s) <> 1 then bad := concat_ws(', ', bad, 'başka daireler'); end if;
  if (select count(*) from public.residents where site_id = s) <> 1 or (select count(*) from public.unit_residents where site_id = s) <> 1 then bad := concat_ws(', ', bad, 'sakin rehberi'); end if;
  if (select count(*) from public.invites) + (select count(*) from public.memberships) > 0 then bad := concat_ws(', ', bad, 'davet/geçmiş/üyelik'); end if;
  if (select count(*) from public.push_tokens) <> 1 then bad := concat_ws(', ', bad, 'başkasının telefon kaydı'); end if;
  if (select count(*) from public.profiles where user_id in (u_a, u_a2, u_m, u_c)) > 0 then bad := concat_ws(', ', bad, 'başka dairenin sakin profili (telefon)'); end if;
  if (select count(*) from public.platform_admins) > 0 then bad := concat_ws(', ', bad, 'sistem yöneticileri'); end if;
  if bad is null then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başka dairenin sakini görüyor: ' || bad; end if;

  -- Profil görme kuralı: sakin → görevliler ve aynı dairedekiler; görevli → herkes; dışarıdaki → kimse
  bad := null;
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
  if not public.can_see_user(u_y) or not public.can_see_user(u_d) or not public.can_see_user(u_a2) then bad := concat_ws(', ', bad, 'sakin görevliyi/ev arkadaşını göremiyor'); end if;
  if public.can_see_user(u_b) then bad := concat_ws(', ', bad, 'sakin komşusunu görüyor'); end if;
  perform set_config('request.jwt.claims', json_build_object('sub', u_y, 'role', 'authenticated')::text, true);
  if not public.can_see_user(u_a) or not public.can_see_user(u_d) then bad := concat_ws(', ', bad, 'yönetici sakini göremiyor'); end if;
  perform set_config('request.jwt.claims', json_build_object('sub', u_y2, 'role', 'authenticated')::text, true);
  if public.can_see_user(u_a) or public.can_see_user(u_y) then bad := concat_ws(', ', bad, 'başka site yöneticisi görüyor'); end if;
  perform set_config('request.jwt.claims', json_build_object('sub', u_m, 'role', 'authenticated')::text, true);
  if public.can_see_user(u_y) then bad := concat_ws(', ', bad, 'taşınmış sakin görüyor'); end if;
  reset role;
  if bad is null then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: profil görme: ' || bad; end if;

  -- W1–W8: doğrudan yazma denemeleri
  -- W1 başka sitenin yöneticisi değiştiremez/silemez/ekleyemez
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_y2, 'role', 'authenticated')::text, true);
  bad := null;
  update public.blocks set name = 'X' where site_id = s; get diagnostics n = row_count; if n > 0 then bad := concat_ws(', ', bad, 'blok değişti'); end if;
  update public.units set no = '99' where site_id = s; get diagnostics n = row_count; if n > 0 then bad := concat_ws(', ', bad, 'daire değişti'); end if;
  update public.sites set name = 'X' where id = s; get diagnostics n = row_count; if n > 0 then bad := concat_ws(', ', bad, 'site değişti'); end if;
  update public.memberships set ended_on = current_date where site_id = s; get diagnostics n = row_count; if n > 0 then bad := concat_ws(', ', bad, 'üyelik kapandı'); end if;
  delete from public.units where site_id = s; get diagnostics n = row_count; if n > 0 then bad := concat_ws(', ', bad, 'daire silindi'); end if;
  delete from public.blocks where site_id = s; get diagnostics n = row_count; if n > 0 then bad := concat_ws(', ', bad, 'blok silindi'); end if;
  reset role;
  if bad is null then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başka site yöneticisi yazdı: ' || bad; end if;

  -- W2–W8: izin verilmeyen yazmalar hata vermeli (her biri ayrı)
  foreach q in array array[
      format('%s|insert into public.blocks (site_id, name) values (%L, %L)', u_y2, s, 'Z'),
      format('%s|insert into public.units (site_id, block_id, no) values (%L, %L, %L)', u_a, s, blk, '9'),
      format('%s|update public.residents set user_id = %L where site_id = %L', u_y, u_y2, s),
      format('%s|update public.memberships set user_id = %L where user_id = %L', u_y, u_r, u_d),
      format('%s|update public.memberships set role = %L where user_id = %L', u_y, 'yonetici', u_d),
      format('%s|update public.profiles set phone = %L where user_id = %L', u_a, '905329999999', u_a),
      format('%s|insert into public.sites (name, type) values (%L, %L)', u_y, 'Sahte', 'apartman')] loop
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', split_part(q, '|', 1), 'role', 'authenticated')::text, true);
    begin
      execute split_part(q, '|', 2);
      kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: izin verilmeyen yazma çalıştı: ' || split_part(q, '|', 2);
    exception when insufficient_privilege then gecti := gecti + 1;
              when others then kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: izin yok demeden başka hatayla durdu (yazma izni var): ' || split_part(q, '|', 2);
    end;
    reset role;
  end loop;

  -- W9: sakin başkasının telefon kaydını silemez, daireleri değiştiremez; yönetici siteyi değiştiremez (sadece sistem yöneticisi)
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
  delete from public.push_tokens where token = 'ExponentPushToken[gt-b]'; get diagnostics n = row_count;
  update public.units set no = '77' where site_id = s;
  perform set_config('request.jwt.claims', json_build_object('sub', u_y, 'role', 'authenticated')::text, true);
  update public.sites set name = 'Y değiştirdi' where id = s;
  reset role;
  if n = 0 and (select count(*) from public.units where site_id = s and no = '77') = 0 and (select name from public.sites where id = s) = 'GT Site'
  then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: sakin/yönetici izin dışı satır değiştirdi'; end if;

  -- W10: uygulamanın kullandığı yazmalar hâlâ çalışır (yönetici danışmanın erişimini kapatır, kişi adını düzeltir)
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_y, 'role', 'authenticated')::text, true);
  update public.memberships set ended_on = current_date where user_id = u_d and site_id = s; get diagnostics n = row_count;
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
  update public.profiles set full_name = 'GT Malik Yeni' where user_id = u_a;
  reset role;
  if n = 1 and (select full_name from public.profiles where user_id = u_a) = 'GT Malik Yeni' then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: uygulamanın izinli yazması çalışmadı'; end if;
  -- danışma yeniden eklenir (kapanan üyelik geri açılmaz)
  insert into public.memberships (user_id, site_id, role) values (u_d, s, 'danisma');

  -- F1–F3: fonksiyonla saldırı (her çağrı hata vermeli)
  foreach q in array array[
      format('%s|select public.create_invite(%L, %L, %L, %L, %L, %L)', u_y2, s, 'sakin', 'Saldırgan', '905320007098', d1, 'malik'),
      format('%s|select public.create_invite(%L, %L, %L, %L)', u_y2, s, 'danisma', 'Saldırgan', '905320007098'),
      format('%s|select public.cancel_invite(%L)', u_y2, inv),
      format('%s|select public.set_ticket_status(%L, %L, null)', u_y2, t1, 'tamamlandi'),
      format('%s|select public.add_ticket_note(%L, %L)', u_y2, t1, 'x'),
      format('%s|select public.record_package(gen_random_uuid(), %L, null)', u_d2, d1),
      format('%s|select public.deliver_package(%L, %L)', u_d2, pk, 'x'),
      format('%s|select public.record_visitor(gen_random_uuid(), %L, %L, null)', u_d2, d1, 'Saldırgan'),
      format('%s|select public.mark_visitor_departed(%L)', u_d2, vi),
      format('%s|select public.end_residency(%L)', u_y2, ur_a),
      format('%s|select public.create_ticket(gen_random_uuid(), %L, %L, %L, %L, null, false)', u_c, d1, 'ariza', 'daire', 'Sahte kayıt')] loop
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', split_part(q, '|', 1), 'role', 'authenticated')::text, true);
    begin
      execute split_part(q, '|', 2);
      bad := split_part(q, '|', 2);
    exception when others then bad := null;
    end;
    reset role;
    exit when bad is not null;
  end loop;
  if bad is null then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başka site fonksiyonla işlem yaptı: ' || bad; end if;

  foreach q in array array[
      format('%s|select public.set_ticket_status(%L, %L, null)', u_a, t1, 'tamamlandi'),
      format('%s|select public.add_ticket_note(%L, %L)', u_a, t2, 'x'),
      format('%s|select public.resolve_ticket(%L, true, null)', u_a, t2),
      format('%s|select public.record_package(gen_random_uuid(), %L, null)', u_a, d1),
      format('%s|select public.record_visitor(gen_random_uuid(), %L, %L, null)', u_a, d1, 'Kendim'),
      format('%s|select public.create_invite(%L, %L, %L, %L, %L, %L)', u_a, s, 'sakin', 'Arkadaşım', '905320007097', d1, 'kiraci'),
      format('%s|select public.create_invite(%L, %L, %L, %L)', u_d, s, 'danisma', 'Arkadaşım', '905320007097'),
      format('%s|select public.create_invite(%L, %L, %L, %L)', u_y, t_site, 'yonetici', 'Arkadaşım', '905320007097'),
      format('%s|select public.end_residency(%L)', u_a, ur_a),
      format('%s|select public.platform_site_stats()', u_y),
      format('%s|select public.create_ticket(gen_random_uuid(), %L, %L, %L, %L, null, false)', u_a, d2, 'ariza', 'daire', 'Komşu adına')] loop
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', split_part(q, '|', 1), 'role', 'authenticated')::text, true);
    begin
      execute split_part(q, '|', 2);
      bad := split_part(q, '|', 2);
    exception when others then bad := null;
    end;
    reset role;
    exit when bad is not null;
  end loop;
  if bad is null then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: rolünün dışında işlem yapıldı: ' || bad; end if;

  foreach q in array array['select public.files_to_purge()', 'select public.health_report()', 'select public.mark_media_deleted(array[''x''])',
                           format('select public.notify_users(array[%L]::uuid[], %L, %L, %L)', u_b, 'Sahte', 'Sahte', '/'), 'select public.purge_old_visitors()'] loop
    set local role authenticated;
    perform set_config('request.jwt.claims', json_build_object('sub', u_y, 'role', 'authenticated')::text, true);
    begin
      execute q;
      bad := q;
    exception when insufficient_privilege then bad := null;
    end;
    reset role;
    exit when bad is not null;
  end loop;
  if bad is null then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: sunucu fonksiyonu uygulamadan çağrıldı: ' || bad; end if;

  -- A1: girişsiz (anon) hiçbir tabloyu okuyamaz, davet önizlemesi dışında fonksiyon çağıramaz
  set local role anon;
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  n := 0;
  foreach tbl in array site_tables || array['profiles', 'push_tokens', 'platform_admins'] loop
    begin
      execute format('select count(*) from public.%I', tbl);
      n := n + 1;
    exception when insufficient_privilege then null;
    end;
  end loop;
  begin
    perform public.my_context();
    n := n + 1;
  exception when insufficient_privilege then null;
  end;
  reset role;
  if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: girişsiz %s yere erişti', n); end if;

  -- S1–S6: dosya deposu
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
  begin
    insert into storage.objects (bucket_id, name, metadata) values ('kayitlar', s || '/' || t1 || '/b.jpg', '{"mimetype": "image/jpeg", "size": 10}');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: komşunun kaydına dosya yüklendi';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;
  begin
    insert into storage.objects (bucket_id, name, metadata) values ('profil', u_a || '/x.jpg', '{"mimetype": "image/jpeg", "size": 10}');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başkasının profil klasörüne yüklendi';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;
  begin
    perform public.set_my_avatar(u_a || '/x.jpg');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başkasının dosyası profil resmi yapıldı';
  exception when others then gecti := gecti + 1;
  end;

  -- Kayıt başına en fazla 5 dosya (bağlanmamış yüklemeler de sayılır); tür depodaki dosyadan alınır
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
  insert into storage.objects (bucket_id, name, metadata) values ('kayitlar', s || '/' || t1 || '/v.mp4', '{"mimetype": "video/mp4", "size": 900000}');
  begin
    perform public.add_ticket_media(t1, s || '/' || t1 || '/v.mp4', 'foto', 10, null);
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: video fotoğraf diye eklendi';
  exception when sqlstate '22023' then gecti := gecti + 1;
  end;
  insert into storage.objects (bucket_id, name, metadata) values ('kayitlar', s || '/' || t1 || '/c.jpg', '{"mimetype": "image/jpeg", "size": 10}');
  insert into storage.objects (bucket_id, name, metadata) values ('kayitlar', s || '/' || t1 || '/d.jpg', '{"mimetype": "image/jpeg", "size": 10}');
  insert into storage.objects (bucket_id, name, metadata) values ('kayitlar', s || '/' || t1 || '/e.jpg', '{"mimetype": "image/jpeg", "size": 10}');
  begin
    insert into storage.objects (bucket_id, name, metadata) values ('kayitlar', s || '/' || t1 || '/f.jpg', '{"mimetype": "image/jpeg", "size": 10}');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: kayda 6. dosya yüklendi';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;
  -- Profil klasöründe en fazla 3 dosya
  n := 0;
  for i in 1 .. 4 loop
    begin
      insert into storage.objects (bucket_id, name, metadata) values ('profil', u_a || '/' || i || '.jpg', '{"mimetype": "image/jpeg", "size": 10}');
      n := n + 1;
    exception when insufficient_privilege then null;
    end;
  end loop;
  reset role;
  if n = 3 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || format(E'\nKALDI: profil klasörüne %s dosya yüklendi (3 olmalı)', n); end if;

  -- T1–T3: temizlik ve sağlık (sunucu işi)
  update public.tickets set status = 'tamamlandi', closed_at = now() - interval '7 months' where id = t2;
  insert into storage.objects (bucket_id, name, metadata) values ('kayitlar', s || '/' || t2 || '/v.mp4', '{"mimetype": "video/mp4", "size": 900000}');
  insert into public.ticket_media (ticket_id, site_id, kind, path, size_bytes) values (t2, s, 'video', s || '/' || t2 || '/v.mp4', 900000);
  update storage.objects set created_at = now() - interval '2 days' where bucket_id = 'kayitlar' and name = s || '/' || t1 || '/c.jpg';
  if exists (select 1 from public.files_to_purge() f where f.path = s || '/' || t2 || '/v.mp4' and f.reason = 'video')
     and not exists (select 1 from public.files_to_purge() f where f.path = s || '/' || t1 || '/a.jpg')
  then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: süresi dolan video listede yok ya da fotoğraf silinecek sanıldı'; end if;
  if exists (select 1 from public.files_to_purge() f where f.path = s || '/' || t1 || '/c.jpg' and f.reason = 'sahipsiz')
     and not exists (select 1 from public.files_to_purge() f where f.path = s || '/' || t1 || '/v.mp4')
  then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: sahipsiz dosya kuralı yanlış'; end if;
  perform public.health_report();
  gecti := gecti + 1;

  raise exception 'SONUÇ: % test geçti, % test kaldı.%', gecti, kaldi,
    case when kaldi = 0 then ' Her şey yolunda.' else rapor end;
end;
$$;
