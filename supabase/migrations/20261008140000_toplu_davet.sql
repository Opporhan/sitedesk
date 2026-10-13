-- Toplu davet (kullanıcı onayı 08.10.2026): yönetici sakin listesini (Excel'den yapıştırarak) tek seferde davet eder.
-- • create_invites_bulk: her satır için create_invite ile aynı kurallar (sakin rehbere ve daireye eklenir); en fazla 1000 satır,
--   tek işlem (biri hatalıysa hiçbiri yazılmaz). Zaten o dairede uygulamayı kullanan kişi atlanır. Toplu davet 30 gün geçerlidir.
-- • WhatsApp turu: mesajı açılan davet "gönderildi" işaretlenir (mark_invite_sent); tur kaldığı yerden sürer.
set local lock_timeout = '15s';
set local statement_timeout = '60s';

alter table public.invites add column sent_at timestamptz;

create function public.create_invites_bulk(p_site_id uuid, p_rows jsonb)
returns table (status text, invite_id uuid, full_name text, phone text, unit_id uuid)
language plpgsql security definer set search_path = ''
as $$
declare
  r jsonb;
  v_code text;
  v_inv uuid;
begin
  if not public.has_site_role(p_site_id, '{yonetici}') then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'Liste boş' using errcode = '22023'; end if;
  if jsonb_array_length(p_rows) > 1000 then raise exception 'Bir seferde en fazla 1000 kişi davet edilebilir' using errcode = 'SD040'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    if r ->> 'phone' !~ '^90[0-9]{10}$' then raise exception 'Telefon hatalı: %', r ->> 'phone' using errcode = '22023'; end if;
    if r ->> 'relation' not in ('malik', 'kiraci') then raise exception 'Malik/kiracı hatalı' using errcode = '22023'; end if;
    -- Bu dairede zaten uygulamayı kullanıyorsa davet gerekmez
    if exists (select 1 from public.residents x join public.unit_residents ur on ur.resident_id = x.id and ur.ended_on is null
               where x.site_id = p_site_id and x.phone = r ->> 'phone' and x.user_id is not null and ur.unit_id = (r ->> 'unit_id')::uuid) then
      status := 'zaten'; invite_id := null; full_name := r ->> 'full_name'; phone := r ->> 'phone'; unit_id := (r ->> 'unit_id')::uuid;
      return next;
      continue;
    end if;
    select c.code into v_code from public.create_invite(p_site_id, 'sakin', r ->> 'full_name', r ->> 'phone', (r ->> 'unit_id')::uuid, r ->> 'relation') c;
    update public.invites i set expires_at = now() + interval '30 days' where i.code = v_code returning i.id into v_inv;
    status := 'davet'; invite_id := v_inv; full_name := trim(r ->> 'full_name'); phone := r ->> 'phone'; unit_id := (r ->> 'unit_id')::uuid;
    return next;
  end loop;
end;
$$;
revoke execute on function public.create_invites_bulk(uuid, jsonb) from public, anon;
grant execute on function public.create_invites_bulk(uuid, jsonb) to authenticated;

create function public.mark_invite_sent(p_invite_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_site uuid;
begin
  select site_id into v_site from public.invites where id = p_invite_id and role in ('sakin', 'danisma');
  if v_site is null or not public.has_site_role(v_site, '{yonetici}') then raise exception 'Yetkiniz yok' using errcode = '42501'; end if;
  update public.invites set sent_at = coalesce(sent_at, now()) where id = p_invite_id;
end;
$$;
revoke execute on function public.mark_invite_sent(uuid) from public, anon;
grant execute on function public.mark_invite_sent(uuid) to authenticated;
