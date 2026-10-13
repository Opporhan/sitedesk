-- Sakin işleri (kullanıcı kararı, 05.10.2026): sakin uygulamadan
-- • ARIZA bildirir (her pakette; fotoğraf en fazla 3, sunucu yükler). Arıza takibi Başlangıç'ta da açılır (yönetici).
-- • Yönetime TALEP / ÖNERİ / ŞİKÂYET yazar; yönetim cevaplar, cevap sakine mesaj + bildirim olarak gider. Danışma göremez.
-- • ÖNEMLİ TELEFONLAR: yönetim girer (danışma, yönetim, görevliler, acil), sakin tek dokunuşla arar.
-- Kötüye kullanıma karşı: bir sakin günde en fazla 10 arıza ve 10 talep yazabilir.
-- Mevcut kayıtlar değişmez.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

alter table public.tickets add column resident_id uuid references public.residents (id) on delete set null;

alter table public.resident_messages drop constraint resident_messages_kind_check;
alter table public.resident_messages add constraint resident_messages_kind_check check (kind in ('odeme', 'hatirlatma', 'kargo', 'ariza', 'duyuru', 'talep'));

-- ---------------------------------------------------------------
-- Arıza bildir (sakin)
-- ---------------------------------------------------------------
create function public.resident_create_ticket(p_unit_id uuid, p_description text, p_urgent boolean default false)
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
  if v_resident is null then
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
revoke execute on function public.resident_create_ticket(uuid, text, boolean) from public, anon;
grant execute on function public.resident_create_ticket(uuid, text, boolean) to authenticated;

-- Fotoğraf yüklemeden önce (sunucu sorar): bu açık arızayı bu sakin mi bildirdi? Sitesini döner.
create function public.my_open_ticket_site(p_ticket_id uuid)
returns uuid
language sql stable security definer set search_path = ''
as $$
  select t.site_id from public.tickets t join public.residents r on r.id = t.resident_id
  where t.id = p_ticket_id and r.user_id = auth.uid() and t.status <> 'tamamlandi'
$$;
revoke execute on function public.my_open_ticket_site(uuid) from public, anon;
grant execute on function public.my_open_ticket_site(uuid) to authenticated;

-- ---------------------------------------------------------------
-- Önemli telefonlar
-- ---------------------------------------------------------------
create table public.site_contacts (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  name text not null check (length(trim(name)) between 2 and 80),
  phone text not null check (phone ~ '^[1-9][0-9]{2,14}$'),
  note text check (note is null or length(note) <= 120),
  sort smallint not null default 0,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null
);
create index on public.site_contacts (site_id);
alter table public.site_contacts enable row level security;
revoke all on public.site_contacts from public, anon, authenticated;
grant select, delete on public.site_contacts to authenticated;
grant insert (site_id, name, phone, note, sort) on public.site_contacts to authenticated;
grant update (name, phone, note, sort) on public.site_contacts to authenticated;
create policy "telefon görme" on public.site_contacts for select to authenticated
  using ((select public.has_site_role(site_id, '{yonetici,danisma}')) or (select public.is_site_viewer(site_id)));
create policy "telefon ekleme" on public.site_contacts for insert to authenticated
  with check ((select public.has_site_role(site_id, '{yonetici}')));
create policy "telefon düzenleme" on public.site_contacts for update to authenticated
  using ((select public.has_site_role(site_id, '{yonetici}'))) with check ((select public.has_site_role(site_id, '{yonetici}')));
create policy "telefon silme" on public.site_contacts for delete to authenticated
  using ((select public.has_site_role(site_id, '{yonetici}')));

-- ---------------------------------------------------------------
-- Talep / öneri / şikâyet
-- ---------------------------------------------------------------
create table public.resident_requests (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  resident_id uuid not null references public.residents (id) on delete cascade,
  kind text not null check (kind in ('talep', 'oneri', 'sikayet')),
  body text not null check (length(trim(body)) between 5 and 2000),
  status text not null default 'acik' check (status in ('acik', 'cevaplandi')),
  reply text check (reply is null or length(trim(reply)) between 2 and 2000),
  replied_at timestamptz,
  replied_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);
create index on public.resident_requests (site_id, created_at desc);
alter table public.resident_requests enable row level security;
revoke all on public.resident_requests from public, anon, authenticated;
grant select on public.resident_requests to authenticated;
create policy "talep görme" on public.resident_requests for select to authenticated
  using ((select public.has_site_role(site_id, '{yonetici}')) or (select public.is_site_viewer(site_id)));

create function public.create_request(p_site_id uuid, p_kind text, p_body text)
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
  if v_resident is null then
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
revoke execute on function public.create_request(uuid, text, text) from public, anon;
grant execute on function public.create_request(uuid, text, text) to authenticated;

create function public.reply_request(p_request_id uuid, p_reply text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_req public.resident_requests;
begin
  select * into v_req from public.resident_requests where id = p_request_id;
  if not found or not public.has_site_role(v_req.site_id, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if coalesce(length(trim(p_reply)), 0) not between 2 and 2000 then
    raise exception 'Cevabı yazın' using errcode = '22023';
  end if;
  update public.resident_requests set status = 'cevaplandi', reply = trim(p_reply), replied_at = now(), replied_by = auth.uid()
  where id = p_request_id;
  insert into public.resident_messages (site_id, resident_id, kind, title, body, url)
  values (v_req.site_id, v_req.resident_id, 'talep', 'Yönetimden cevap', trim(p_reply), '/sakin/iletisim');
end;
$$;
revoke execute on function public.reply_request(uuid, text) from public, anon;
grant execute on function public.reply_request(uuid, text) to authenticated;

-- ---------------------------------------------------------------
-- Sakinin ana sayfası: arızalar her pakette; önemli telefonlar ve talepler eklendi
-- ---------------------------------------------------------------
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
    where r.user_id = auth.uid()
      and exists (select 1 from public.unit_residents ur where ur.resident_id = r.id and ur.ended_on is null)
  ), '[]'::jsonb);
end;
$$;
