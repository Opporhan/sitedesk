-- Liste deposu testi: yönetici kendi klasörüne liste dosyası yükler; başkasının klasörüne, danışma ve sakin yükleyemez;
-- kimse okuyamaz; 1 saatten eski dosya temizlik listesine girer. Sonunda HER ŞEY GERİ ALINIR.
-- Beklenen: "SONUÇ: 5 test geçti, 0 test kaldı. Her şey yolunda."
do $$
declare
  u_yon uuid := gen_random_uuid(); u_dan uuid := gen_random_uuid(); s uuid; n int;
  gecti int := 0; kaldi int := 0; rapor text := '';
begin
  insert into auth.users (id, email) values (u_yon, 'ld-yon@example.com'), (u_dan, 'ld-dan@example.com');
  insert into public.sites (name, type) values ('LD Site', 'apartman') returning id into s;
  insert into public.memberships (user_id, site_id, role) values (u_yon, s, 'yonetici'), (u_dan, s, 'danisma');

  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', u_yon, 'role', 'authenticated')::text, true);
  insert into storage.objects (bucket_id, name) values ('listeler', u_yon || '/liste.xlsx');
  gecti := gecti + 1;
  begin
    insert into storage.objects (bucket_id, name) values ('listeler', u_dan || '/liste.xlsx');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: başkasının klasörüne yüklendi';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;
  select count(*) into n from storage.objects where bucket_id = 'listeler';
  if n = 0 then gecti := gecti + 1; else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: liste dosyası okunabiliyor'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', u_dan, 'role', 'authenticated')::text, true);
  begin
    insert into storage.objects (bucket_id, name) values ('listeler', u_dan || '/liste.xlsx');
    kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: danışma liste yükledi';
  exception when insufficient_privilege then gecti := gecti + 1;
  end;
  reset role;

  update storage.objects set created_at = now() - interval '2 hours' where bucket_id = 'listeler' and name = u_yon || '/liste.xlsx';
  if exists (select 1 from public.files_to_purge() f where f.bucket = 'listeler' and f.path = u_yon || '/liste.xlsx') then gecti := gecti + 1;
  else kaldi := kaldi + 1; rapor := rapor || E'\nKALDI: eski liste dosyası temizlik listesinde yok'; end if;

  raise exception 'SONUÇ: % test geçti, % test kaldı.%', gecti, kaldi,
    case when kaldi = 0 then ' Her şey yolunda.' else rapor end;
end;
$$;
