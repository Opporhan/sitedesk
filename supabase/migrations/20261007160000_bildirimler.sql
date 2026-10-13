-- Adım 7: telefon bildirimleri (kullanıcı onayı 07.10.2026)
-- • Telefonlar Expo bildirim kimliğiyle (token) kaydolur; herkes sadece kendi telefonunu görür/siler.
-- • Bildirimi veritabanı gönderir (pg_net ile Expo'nun ücretsiz bildirim servisine; istek beklemez, işlemi yavaşlatmaz).
-- • Kime: yeni ve acil kayıt + "sorun devam ediyor" → sitenin YÖNETİCİLERİ (kullanıcı kararı: danışmaya değil).
--         durum değişikliği, yönetim/danışma cevabı, kargo → o dairenin uygulamadaki sakinleri.
--   İşlemi yapan kişinin kendisine gitmez. Bildirime dokununca ilgili ekran açılır (data.url).

set local lock_timeout = '15s';
set local statement_timeout = '60s';

create extension if not exists pg_net;

create table public.push_tokens (
  token text primary key check (token ~ '^(Exponent|Expo)PushToken\[.+\]$'),
  user_id uuid not null references auth.users (id) on delete cascade,
  platform text check (platform in ('ios', 'android')),
  updated_at timestamptz not null default now()
);
create index on public.push_tokens (user_id);
alter table public.push_tokens enable row level security;
revoke all on public.push_tokens from anon, authenticated;
grant select, delete on public.push_tokens to authenticated;
create policy "kendi telefonum" on public.push_tokens for select to authenticated using (user_id = (select auth.uid()));
create policy "kendi telefonumu silerim" on public.push_tokens for delete to authenticated using (user_id = (select auth.uid()));

-- Telefonu kaydet (aynı telefon başka hesaba geçtiyse yeni hesaba bağlanır)
create function public.register_push_token(p_token text, p_platform text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  insert into public.push_tokens (token, user_id, platform) values (p_token, auth.uid(), p_platform)
  on conflict (token) do update set user_id = excluded.user_id, platform = excluded.platform, updated_at = now();
end;
$$;
revoke execute on function public.register_push_token(text, text) from public, anon;
grant execute on function public.register_push_token(text, text) to authenticated;

-- Kişilere bildirim gönder (işlemi yapan hariç); Expo isteği en fazla 100 mesaj alır
create function public.notify_users(p_users uuid[], p_title text, p_body text, p_url text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_msgs jsonb;
  v_chunk jsonb;
  i int := 0;
begin
  select coalesce(jsonb_agg(jsonb_build_object('to', t.token, 'title', left(p_title, 120), 'body', left(coalesce(p_body, ''), 300),
                                                'sound', 'default', 'priority', 'high', 'channelId', 'default', 'data', jsonb_build_object('url', p_url))), '[]'::jsonb)
  into v_msgs
  from public.push_tokens t
  where t.user_id = any (p_users) and t.user_id is distinct from auth.uid();
  while i < jsonb_array_length(v_msgs) loop
    select jsonb_agg(e) into v_chunk from (select e from jsonb_array_elements(v_msgs) with ordinality as x(e, n) where n > i and n <= i + 100) s;
    perform net.http_post(
      url := 'https://exp.host/--/api/v2/push/send',
      body := v_chunk,
      headers := '{"Content-Type": "application/json", "Accept": "application/json"}'::jsonb
    );
    i := i + 100;
  end loop;
end;
$$;
revoke execute on function public.notify_users(uuid[], text, text, text) from public, anon, authenticated;

-- Alıcılar: sitenin aktif yöneticileri · dairenin uygulamadaki aktif sakinleri
create function public.site_manager_users(p_site_id uuid)
returns uuid[] language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(m.user_id), '{}') from public.memberships m join public.sites s on s.id = m.site_id
  where m.site_id = p_site_id and m.role = 'yonetici' and m.ended_on is null and s.active
$$;
create function public.unit_resident_users(p_unit_id uuid)
returns uuid[] language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(distinct r.user_id), '{}') from public.unit_residents ur
  join public.residents r on r.id = ur.resident_id join public.sites s on s.id = ur.site_id
  where ur.unit_id = p_unit_id and ur.ended_on is null and r.user_id is not null and s.active
$$;
create function public.unit_label(p_unit_id uuid)
returns text language sql stable security definer set search_path = ''
as $$ select b.name || '-' || u.no from public.units u join public.blocks b on b.id = u.block_id where u.id = p_unit_id $$;
revoke execute on function public.site_manager_users(uuid), public.unit_resident_users(uuid), public.unit_label(uuid) from public, anon, authenticated;

-- Yeni kayıt → yöneticiler (acilse başlıkta belirtilir)
create function public.notify_ticket_created()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_kind text := case new.kind when 'ariza' then 'arıza' when 'talep' then 'talep' when 'sikayet' then 'şikâyet' else 'öneri' end;
begin
  perform public.notify_users(public.site_manager_users(new.site_id),
    case when new.urgent then '🔴 ACİL · ' || public.unit_label(new.unit_id) else 'Yeni ' || v_kind || ' · ' || public.unit_label(new.unit_id) end,
    new.title, '/kayit/' || new.id);
  return new;
end;
$$;
create trigger bildirim after insert on public.tickets for each row execute function public.notify_ticket_created();

-- Kayıt geçmişi: yönetim/danışma durum değiştirdi ya da cevap yazdı → dairenin sakinleri; sakin "devam ediyor" dedi → yöneticiler
create function public.notify_ticket_event()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_t public.tickets;
  v_status text := case new.status when 'alindi' then 'Alındı' when 'inceleniyor' then 'İnceleniyor' when 'yapiliyor' then 'Yapılıyor' when 'tamamlandi' then 'Tamamlandı' else new.status end;
begin
  select * into v_t from public.tickets where id = new.ticket_id;
  if new.author_role in ('yonetici', 'danisma') then
    if new.kind = 'durum' then
      perform public.notify_users(public.unit_resident_users(v_t.unit_id), v_t.title,
        'Durum: ' || v_status || coalesce(' · ' || new.body, ''), '/kayit/' || v_t.id);
    elsif new.kind = 'not' then
      perform public.notify_users(public.unit_resident_users(v_t.unit_id), 'Yönetimden cevap · ' || v_t.title, new.body, '/kayit/' || v_t.id);
    end if;
  elsif new.kind = 'sonuc' and new.status = 'devam' then
    perform public.notify_users(public.site_manager_users(v_t.site_id), public.unit_label(v_t.unit_id) || ': Sorun devam ediyor',
      v_t.title || coalesce(' · ' || new.body, ''), '/kayit/' || v_t.id);
  end if;
  return new;
end;
$$;
create trigger bildirim after insert on public.ticket_events for each row execute function public.notify_ticket_event();

-- Kargo geldi → dairenin sakinleri
create function public.notify_package()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  perform public.notify_users(public.unit_resident_users(new.unit_id), 'Kargonuz geldi',
    public.unit_label(new.unit_id) || ' adına kargonuz danışmaya ulaştı. Danışmadan teslim alabilirsiniz.', '/sakin/kargo');
  return new;
end;
$$;
create trigger bildirim after insert on public.packages for each row execute function public.notify_package();
