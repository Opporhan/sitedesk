-- Sakin uygulaması Standart ve Tam pakette (kullanıcı kararı, 05.10.2026; Başlangıç'tan çıktı).
-- Başlangıç'ta: sakin hesabı açılamaz, sakin giremez/bir şey göremez, sakine uygulama içi mesaj oluşmaz,
-- sakin arıza ve talep yazamaz. Sakin rehberi ve WhatsApp hatırlatma Başlangıç'ta kalır.
-- Paket düşünce hiçbir kayıt silinmez: hesaplar bağlı kalır ama gizlenir; paket yükselince olduğu gibi geri gelir.
-- Arıza takibi (danışma ekranı) yine Standart ve Tam pakette (uygulamada).

set local lock_timeout = '15s';
set local statement_timeout = '60s';

create function public.site_has_resident_app(p_site_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.sites where id = p_site_id and package in ('standart', 'tam')) $$;
revoke execute on function public.site_has_resident_app(uuid) from public, anon;
grant execute on function public.site_has_resident_app(uuid) to authenticated;

-- Hesap açma kontrolü: paket şartı eklendi (SD003: "bu pakette yok")
create or replace function public.resident_account_phone(p_resident_id uuid)
returns text
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_site uuid;
  v_phone text;
begin
  select site_id, phone into v_site, v_phone from public.residents where id = p_resident_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if not public.site_has_resident_app(v_site) then
    raise exception 'Sakin uygulaması Standart ve Tam pakette' using errcode = 'SD003';
  end if;
  if v_phone is null then
    raise exception 'Telefonu olmayan sakine hesap açılamaz' using errcode = '22023';
  end if;
  return v_phone;
end;
$$;

-- Mesaj alacak hesaplı sakinler: sadece sakin uygulaması olan pakette
create or replace function public.unit_app_residents(p_unit_id uuid, p_on date default null)
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select distinct r.id
  from public.unit_residents ur
  join public.residents r on r.id = ur.resident_id
  join public.sites s on s.id = r.site_id
  where ur.unit_id = p_unit_id and ur.ended_on is null and r.user_id is not null and s.package in ('standart', 'tam')
    and (p_on is null or ur.relation = 'malik' or ur.start_unknown or p_on >= ur.started_on)
$$;

create or replace function public.message_on_announcement()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.site_has_resident_app(new.site_id) then
    return null;
  end if;
  insert into public.resident_messages (site_id, resident_id, kind, title, body, url)
  select distinct new.site_id, r.id, 'duyuru', left(new.title, 120), left(new.body, 2000), '/sakin'
  from public.residents r
  where r.site_id = new.site_id and r.user_id is not null
    and exists (select 1 from public.unit_residents ur where ur.resident_id = r.id and ur.ended_on is null);
  return null;
end;
$$;

-- Sakin arıza bildirir: sadece sakin uygulaması olan pakette
create or replace function public.resident_create_ticket(p_unit_id uuid, p_description text, p_urgent boolean default false)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_resident uuid;
  v_site uuid;
  v_id uuid;
begin
  select r.id, r.site_id into v_resident, v_site
  from public.residents r join public.unit_residents ur on ur.resident_id = r.id
  where r.user_id = auth.uid() and ur.unit_id = p_unit_id and ur.ended_on is null
  limit 1;
  if v_resident is null or not public.site_has_resident_app(v_site) then
    raise exception 'Bu birim için arıza bildiremezsiniz' using errcode = '42501';
  end if;
  if coalesce(length(trim(p_description)), 0) not between 5 and 1000 then
    raise exception 'Arızayı kısaca yazın (5-1000 karakter)' using errcode = '22023';
  end if;
  if (select count(*) from public.tickets where resident_id = v_resident and created_at > now() - interval '1 day') >= 10 then
    raise exception 'Bugün çok fazla arıza bildirdiniz; lütfen danışmayı arayın' using errcode = '22023';
  end if;
  insert into public.tickets (site_id, unit_id, description, urgent, resident_id)
  values (v_site, p_unit_id, trim(p_description), coalesce(p_urgent, false), v_resident)
  returning id into v_id;
  return v_id;
end;
$$;

-- Sakin talep yazar: sadece sakin uygulaması olan pakette
create or replace function public.create_request(p_site_id uuid, p_kind text, p_body text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_resident uuid;
  v_id uuid;
begin
  select r.id into v_resident from public.residents r
  where r.user_id = auth.uid() and r.site_id = p_site_id
    and exists (select 1 from public.unit_residents ur where ur.resident_id = r.id and ur.ended_on is null);
  if v_resident is null or not public.site_has_resident_app(p_site_id) then
    raise exception 'Bu siteye yazamazsınız' using errcode = '42501';
  end if;
  if p_kind not in ('talep', 'oneri', 'sikayet') or coalesce(length(trim(p_body)), 0) not between 5 and 2000 then
    raise exception 'Konuyu kısaca yazın (5-2000 karakter)' using errcode = '22023';
  end if;
  if (select count(*) from public.resident_requests where resident_id = v_resident and created_at > now() - interval '1 day') >= 10 then
    raise exception 'Bugün çok fazla mesaj yazdınız; lütfen yarın tekrar deneyin' using errcode = '22023';
  end if;
  insert into public.resident_requests (site_id, resident_id, kind, body) values (p_site_id, v_resident, p_kind, trim(p_body))
  returning id into v_id;
  return v_id;
end;
$$;

-- Sakinin ana sayfası ve özeti: sadece sakin uygulaması olan paketteki siteler
create or replace function public.my_home()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'Europe/Istanbul')::date;
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'site', jsonb_build_object('id', s.id, 'name', s.name, 'address', s.address, 'type', s.type, 'package', s.package, 'is_demo', s.is_demo),
      'resident', jsonb_build_object('id', r.id, 'name', r.full_name),
      'units', coalesce((
        select jsonb_agg(jsonb_build_object(
          'unit_id', u.id,
          'label', b.name || '-' || u.no,
          'relation', ur.relation,
          'since', case when ur.relation = 'kiraci' and not ur.start_unknown then ur.started_on end,
          'dues', coalesce((
            select jsonb_agg(jsonb_build_object('id', d.due_id, 'kind', d.kind, 'period', d.period, 'due_date', d.due_date,
                                                'description', d.description, 'amount', d.amount, 'remaining', d.remaining)
                             order by d.period desc, d.due_date desc)
            from public.due_balances d
            where d.unit_id = u.id and (ur.relation = 'malik' or ur.start_unknown or d.due_date >= ur.started_on)), '[]'::jsonb),
          'payments', coalesce((
            select jsonb_agg(jsonb_build_object('id', p.id, 'amount', p.amount, 'paid_on', p.paid_on, 'note', p.note,
                                                'receipt_year', p.receipt_year, 'receipt_no', p.receipt_no, 'covered', p.covered,
                                                'created_at', p.created_at)
                             order by p.paid_on desc, p.created_at desc)
            from public.payments p
            where p.unit_id = u.id and p.status = 'aktif'
              and (ur.relation = 'malik' or ur.start_unknown or p.paid_on >= ur.started_on)), '[]'::jsonb),
          'packages', case when s.package in ('standart', 'tam') then coalesce((
            select jsonb_agg(jsonb_build_object('received_at', k.received_at) order by k.received_at desc)
            from public.packages k where k.unit_id = u.id and k.delivered_at is null and k.received_at > now() - interval '30 days'), '[]'::jsonb)
            else '[]'::jsonb end,
          -- Danışmanın bu birime kaydettiği misafirler (son 30 gün). Kiracı kendi taşınmasından sonrasını görür;
          -- birimde oturan kiracı varken malik misafirleri görmez (kiracının hanesine ait bilgi).
          'visitors', coalesce((
            select jsonb_agg(jsonb_build_object('name', vz.visitor_name, 'plate', vz.plate, 'arrived_at', vz.arrived_at, 'departed_at', vz.departed_at)
                             order by vz.arrived_at desc)
            from public.visitors vz
            where vz.unit_id = u.id and vz.arrived_at > now() - interval '30 days'
              and (ur.start_unknown or vz.arrived_at >= ur.started_on)
              and (ur.relation = 'kiraci' or not exists (
                select 1 from public.unit_residents k where k.unit_id = u.id and k.relation = 'kiraci' and k.ended_on is null))), '[]'::jsonb),
          'tickets', coalesce((
            select jsonb_agg(jsonb_build_object('id', t.id, 'description', t.description, 'status', t.status, 'urgent', t.urgent,
                                                'created_at', t.created_at, 'closed_at', t.closed_at, 'mine', t.resident_id = r.id,
                                                'photos', (select count(*) from public.ticket_photos ph where ph.ticket_id = t.id))
                             order by t.created_at desc)
            from public.tickets t where t.unit_id = u.id and (t.status <> 'tamamlandi' or t.closed_at > now() - interval '60 days')), '[]'::jsonb)
        ) order by b.name, u.no)
        from public.unit_residents ur
        join public.units u on u.id = ur.unit_id
        join public.blocks b on b.id = u.block_id
        where ur.resident_id = r.id and ur.ended_on is null), '[]'::jsonb),
      -- Önemli telefonlar (yönetim girer)
      'contacts', coalesce((
        select jsonb_agg(jsonb_build_object('name', c.name, 'phone', c.phone, 'note', c.note) order by c.sort, c.name)
        from public.site_contacts c where c.site_id = s.id), '[]'::jsonb),
      -- Sakinin yönetime yazdığı talep/öneriler ve cevapları
      'requests', coalesce((
        select jsonb_agg(jsonb_build_object('id', q.id, 'kind', q.kind, 'body', q.body, 'status', q.status, 'reply', q.reply,
                                            'created_at', q.created_at, 'replied_at', q.replied_at) order by q.created_at desc)
        from (select * from public.resident_requests where resident_id = r.id order by created_at desc limit 30) q), '[]'::jsonb),
      'messages', coalesce((
        select jsonb_agg(jsonb_build_object('id', m.id, 'kind', m.kind, 'title', m.title, 'body', m.body, 'url', m.url,
                                            'created_at', m.created_at, 'read', m.read_at is not null) order by m.created_at desc)
        from (select * from public.resident_messages where resident_id = r.id order by created_at desc limit 50) m), '[]'::jsonb),
      'polls', case when s.package in ('standart', 'tam') then coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', p.id, 'question', p.question, 'options', to_jsonb(p.options), 'voters', p.voters, 'closes_on', p.closes_on,
          'open', p.closed_at is null and p.closes_on >= v_today,
          'units', coalesce((
            select jsonb_agg(jsonb_build_object(
              'unit_id', u.id, 'label', b.name || '-' || u.no,
              'can_vote', (p.voters = 'herkes' or ur.relation = 'malik'),
              'choice', v.choice, 'mine', v.resident_id = r.id) order by b.name, u.no)
            from public.unit_residents ur
            join public.units u on u.id = ur.unit_id
            join public.blocks b on b.id = u.block_id
            left join public.poll_votes v on v.poll_id = p.id and v.unit_id = u.id
            where ur.resident_id = r.id and ur.ended_on is null), '[]'::jsonb),
          'results', case when p.closed_at is not null or p.closes_on < v_today then (
            select jsonb_agg((select count(*) from public.poll_votes v where v.poll_id = p.id and v.choice = i - 1) order by i)
            from generate_series(1, array_length(p.options, 1)) i) end
        ) order by p.created_at desc)
        from public.polls p
        where p.site_id = s.id
          and (p.closed_at is null and p.closes_on >= v_today or coalesce(p.closed_at::date, p.closes_on) > v_today - 90)), '[]'::jsonb)
        else '[]'::jsonb end
    ) order by s.name)
    from public.residents r
    join public.sites s on s.id = r.site_id
    where r.user_id = auth.uid() and s.package in ('standart', 'tam')
      and exists (select 1 from public.unit_residents ur where ur.resident_id = r.id and ur.ended_on is null)
  ), '[]'::jsonb);
end;
$$;

create or replace function public.my_resident_summary()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select case when count(*) = 0 then null else jsonb_build_object(
    'name', min(r.full_name),
    'sites', jsonb_agg(distinct s.name),
    'unread', (select count(*) from public.resident_messages m where m.resident_id in (select r2.id from public.residents r2 join public.sites s2 on s2.id = r2.site_id where r2.user_id = auth.uid() and s2.package in ('standart', 'tam')) and m.read_at is null)
  ) end
  from public.residents r join public.sites s on s.id = r.site_id
  where r.user_id = auth.uid() and s.package in ('standart', 'tam')
    and exists (select 1 from public.unit_residents ur where ur.resident_id = r.id and ur.ended_on is null)
$$;
