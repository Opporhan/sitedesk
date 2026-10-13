-- Anket / oylama (kullanıcı kararı, 05.10.2026; Standart ve Tam pakette)
-- • Yönetici anket açar: soru, 2–8 seçenek, son gün, kimler oy verir (sadece malikler / malik ve kiracılar).
-- • Sakin kendi hesabıyla uygulamadan oy verir. Her villa/daire için tek oy; oyu veren kişi son güne kadar değiştirebilir,
--   aynı birimdeki başka kişi o oyu değiştiremez.
-- • Sonuçları yönetici her zaman, sakinler anket kapandıktan sonra görür. Danışma göremez.
-- • Anket ve oylar sadece fonksiyonlarla yazılır; silinmez (yönetici erken kapatabilir).
-- Mevcut kayıtlar değişmez.

set local lock_timeout = '15s';
set local statement_timeout = '60s';

create table public.polls (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  question text not null check (length(trim(question)) between 5 and 300),
  options text[] not null check (array_length(options, 1) between 2 and 8),
  voters text not null default 'malik' check (voters in ('malik', 'herkes')),
  closes_on date not null,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null
);
create index on public.polls (site_id, created_at desc);

create table public.poll_votes (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references public.polls (id) on delete restrict,
  site_id uuid not null references public.sites (id) on delete restrict,
  unit_id uuid not null references public.units (id) on delete restrict,
  resident_id uuid not null references public.residents (id) on delete restrict,
  choice smallint not null check (choice >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (poll_id, unit_id)
);
create index on public.poll_votes (site_id);

alter table public.polls enable row level security;
alter table public.poll_votes enable row level security;
revoke all on public.polls, public.poll_votes from public, anon, authenticated;
grant select on public.polls, public.poll_votes to authenticated;
create policy "anket görme" on public.polls for select to authenticated
  using ((select public.has_site_role(site_id, '{yonetici}')) or (select public.is_site_viewer(site_id)));
create policy "oy görme" on public.poll_votes for select to authenticated
  using ((select public.has_site_role(site_id, '{yonetici}')) or (select public.is_site_viewer(site_id)));

-- Anket aç (yönetici; Standart ve Tam paket). Sakinlere duyuru metni arşive düşer.
create function public.create_poll(p_site_id uuid, p_question text, p_options text[], p_closes_on date, p_voters text default 'malik')
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
  v_options text[];
  v_site_name text;
begin
  if not public.has_site_role(p_site_id, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if not exists (select 1 from public.sites where id = p_site_id and package in ('standart', 'tam')) then
    raise exception 'Anket Standart ve Tam pakette' using errcode = '42501';
  end if;
  select array_agg(trim(o) order by ord) into v_options
  from unnest(p_options) with ordinality as x(o, ord) where length(trim(o)) > 0;
  if coalesce(array_length(v_options, 1), 0) not between 2 and 8 then
    raise exception 'En az 2, en fazla 8 seçenek yazın' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(v_options) o where length(o) > 120) then
    raise exception 'Seçenek en fazla 120 karakter olabilir' using errcode = '22023';
  end if;
  if (select count(distinct lower(o)) from unnest(v_options) o) <> array_length(v_options, 1) then
    raise exception 'Aynı seçenek iki kez yazılmış' using errcode = '22023';
  end if;
  if p_closes_on is null or p_closes_on < (now() at time zone 'Europe/Istanbul')::date
     or p_closes_on > (now() at time zone 'Europe/Istanbul')::date + 365 then
    raise exception 'Son gün bugün veya sonraki bir yıl içinde olmalı' using errcode = '22023';
  end if;
  if p_voters not in ('malik', 'herkes') then
    raise exception 'Oy verecekler hatalı' using errcode = '22023';
  end if;

  insert into public.polls (site_id, question, options, voters, closes_on)
  values (p_site_id, trim(p_question), v_options, p_voters, p_closes_on)
  returning id into v_id;

  select name into v_site_name from public.sites where id = p_site_id;
  insert into public.announcements (site_id, title, body, auto)
  values (p_site_id, left('Anket: ' || trim(p_question), 120),
          'Sayın ' || v_site_name || ' sakinleri,' || E'\n\n' ||
          'Görüşünüzü almak istediğimiz bir anket açtık: ' || trim(p_question) || E'\n\n' ||
          'Seçenekler: ' || array_to_string(v_options, ', ') || E'\n\n' ||
          'Oyunuzu ' || to_char(p_closes_on, 'DD.MM.YYYY') || ' tarihine kadar SiteDesk uygulamasından verebilirsiniz. ' ||
          'Her villa/daire için bir oy sayılır' ||
          case when p_voters = 'malik' then ' ve oyu malikler verir.' else '.' end || E'\n\n' ||
          v_site_name || ' Yönetimi',
          true);
  return v_id;
end;
$$;
revoke execute on function public.create_poll(uuid, text, text[], date, text) from public, anon;
grant execute on function public.create_poll(uuid, text, text[], date, text) to authenticated;

-- Anketi erken kapat (yönetici)
create function public.close_poll(p_poll_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_site uuid;
begin
  select site_id into v_site from public.polls where id = p_poll_id;
  if v_site is null or not public.has_site_role(v_site, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  update public.polls set closed_at = now() where id = p_poll_id and closed_at is null;
end;
$$;
revoke execute on function public.close_poll(uuid) from public, anon;
grant execute on function public.close_poll(uuid) to authenticated;

-- Oy ver / değiştir (sakin, kendi hesabıyla). Birim başına tek oy; başka kişinin verdiği oy değiştirilemez.
create function public.cast_vote(p_poll_id uuid, p_unit_id uuid, p_choice integer)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_poll public.polls;
  v_resident uuid;
  v_relation text;
  v_existing public.poll_votes;
begin
  select * into v_poll from public.polls where id = p_poll_id;
  if not found or not exists (select 1 from public.sites where id = v_poll.site_id and package in ('standart', 'tam')) then
    raise exception 'Anket bulunamadı' using errcode = '42501';
  end if;
  -- Oy veren: bu sitede bu birimde oturan, hesabı bu kişi olan sakin
  select r.id, ur.relation into v_resident, v_relation
  from public.residents r join public.unit_residents ur on ur.resident_id = r.id
  where r.user_id = auth.uid() and r.site_id = v_poll.site_id and ur.unit_id = p_unit_id and ur.ended_on is null
  order by (ur.relation = 'malik') desc limit 1;
  if v_resident is null then
    raise exception 'Bu birim için oy veremezsiniz' using errcode = '42501';
  end if;
  if v_poll.closed_at is not null or v_poll.closes_on < (now() at time zone 'Europe/Istanbul')::date then
    raise exception 'Anket kapandı' using errcode = '22023';
  end if;
  if p_choice is null or p_choice < 0 or p_choice >= array_length(v_poll.options, 1) then
    raise exception 'Seçenek hatalı' using errcode = '22023';
  end if;
  if v_poll.voters = 'malik' and v_relation <> 'malik' then
    raise exception 'Bu ankette malikler oy verir' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtext('oy-' || p_poll_id::text || p_unit_id::text));
  select * into v_existing from public.poll_votes where poll_id = p_poll_id and unit_id = p_unit_id;
  if found then
    if v_existing.resident_id <> v_resident then
      raise exception 'Bu birim için başka bir sakin oy verdi' using errcode = '23505';
    end if;
    update public.poll_votes set choice = p_choice, updated_at = now() where id = v_existing.id;
  else
    insert into public.poll_votes (poll_id, site_id, unit_id, resident_id, choice)
    values (p_poll_id, v_poll.site_id, p_unit_id, v_resident, p_choice);
  end if;
end;
$$;
revoke execute on function public.cast_vote(uuid, uuid, integer) from public, anon;
grant execute on function public.cast_vote(uuid, uuid, integer) to authenticated;
