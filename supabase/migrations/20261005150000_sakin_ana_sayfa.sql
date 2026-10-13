-- Sakinin ana sayfası (kullanıcı kararı, 05.10.2026): sakin hesabıyla girer, bütün bilgisi tek fonksiyondan gelir.
-- Sakin hiçbir tabloyu doğrudan okuyamaz; sadece kendi kaydına (residents.user_id = kendisi) bağlı olanı görür.
-- • Birim(ler): borç, ödeme (makbuz), hesap dökümü. Kiracı sadece taşınma tarihinden sonraki dönemi görür.
-- • Gelen kutusu (resident_messages, son 50). Standart/Tam pakette ayrıca: duyurular, anketler, bekleyen kargo, arızalar.
-- Mevcut kayıtlar değişmez.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

create function public.my_home()
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
          'tickets', case when s.package in ('standart', 'tam') then coalesce((
            select jsonb_agg(jsonb_build_object('description', t.description, 'status', t.status, 'created_at', t.created_at, 'closed_at', t.closed_at)
                             order by t.created_at desc)
            from public.tickets t where t.unit_id = u.id and (t.status <> 'tamamlandi' or t.closed_at > now() - interval '30 days')), '[]'::jsonb)
            else '[]'::jsonb end
        ) order by b.name, u.no)
        from public.unit_residents ur
        join public.units u on u.id = ur.unit_id
        join public.blocks b on b.id = u.block_id
        where ur.resident_id = r.id and ur.ended_on is null), '[]'::jsonb),
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
revoke execute on function public.my_home() from public, anon;
grant execute on function public.my_home() to authenticated;

-- Üst çubuk ve yönlendirme için: bu kişi aktif bir sakin mi, adı ne, okunmamış mesaj sayısı
create function public.my_resident_summary()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select case when count(*) = 0 then null else jsonb_build_object(
    'name', min(r.full_name),
    'sites', jsonb_agg(distinct s.name),
    'unread', (select count(*) from public.resident_messages m where m.resident_id in (select id from public.residents where user_id = auth.uid()) and m.read_at is null)
  ) end
  from public.residents r join public.sites s on s.id = r.site_id
  where r.user_id = auth.uid()
    and exists (select 1 from public.unit_residents ur where ur.resident_id = r.id and ur.ended_on is null)
$$;
revoke execute on function public.my_resident_summary() from public, anon;
grant execute on function public.my_resident_summary() to authenticated;
