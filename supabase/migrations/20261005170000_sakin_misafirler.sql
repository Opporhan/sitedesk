-- Sakin misafirlerini görür (kullanıcı kararı, 05.10.2026): danışmanın kendi villasına/dairesine kaydettiği misafirler
-- (ad, plaka, giriş ve çıkış saati) sakinin ana sayfasında görünür. Sadece kendi birimi; son 30 gün.
-- Kiracı sadece kendi taşınmasından sonrakileri görür. Birimde oturan kiracı varken malik misafirleri görmez.
-- Ziyaretçi kayıtları zaten 1 yıl sonra silinir (KVKK). Tablolar değişmez; sadece sakinin ana sayfa fonksiyonu yenilenir.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

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
    where r.user_id = auth.uid()
      and exists (select 1 from public.unit_residents ur where ur.resident_id = r.id and ur.ended_on is null)
  ), '[]'::jsonb);
end;
$$;
