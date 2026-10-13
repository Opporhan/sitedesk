-- Paketler (kullanıcı kararı, 03.10.2026): her sitenin bir paketi var — Başlangıç, Standart, Tam.
--   Başlangıç: en fazla 40 birim, 1 kullanıcı · Standart: en fazla 120 birim, 3 kullanıcı · Tam: sınır yok
-- "Kullanıcı" = siteye giriş yapan site yöneticisi ve danışma hesapları (sistem yöneticisi ve salt okunur demo hesabı sayılmaz).
-- Hangi bölümün hangi pakette açık olduğu uygulamada (lib/packages.ts); sınırlar burada, veritabanında uygulanır.
-- Paketi sadece sistem yöneticisi değiştirir (sitelerin güncelleme kuralı zaten sadece ona izin veriyor).
-- Sınırın üstündeki site daha küçük pakete düşürülemez. Paket değişince hiçbir veri silinmez.
-- Mevcut siteler Tam pakette kalır. Uygulamada yeni site açarken paket seçimi zorunludur (varsayılan seçili gelmez).

set local lock_timeout = '15s';
set local statement_timeout = '60s';

alter table public.sites add column package text not null default 'tam' check (package in ('baslangic', 'standart', 'tam'));

create function public.package_label(p text)
returns text language sql immutable set search_path = ''
as $$ select case p when 'baslangic' then 'Başlangıç' when 'standart' then 'Standart' else 'Tam' end $$;

create function public.package_max_units(p text)
returns integer language sql immutable set search_path = ''
as $$ select case p when 'baslangic' then 40 when 'standart' then 120 else null end $$;

create function public.package_max_users(p text)
returns integer language sql immutable set search_path = ''
as $$ select case p when 'baslangic' then 1 when 'standart' then 3 else null end $$;

-- Sitenin kullanıcı sayısı: aktif site yöneticisi ve danışma üyelikleri
create function public.site_user_count(p_site_id uuid)
returns integer language sql stable security definer set search_path = ''
as $$
  select count(*)::integer from public.memberships
  where site_id = p_site_id and role in ('yonetici', 'danisma') and ended_on is null;
$$;
revoke execute on function public.site_user_count(uuid) from public, anon;
grant execute on function public.site_user_count(uuid) to authenticated;

-- Birim sınırı (elle ekleme, toplu yükleme, kurulum rehberi: hepsi buradan geçer)
create function public.enforce_unit_limit()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_package text;
  v_max integer;
  v_count integer;
begin
  select package into v_package from public.sites where id = new.site_id;
  v_max := public.package_max_units(v_package);
  if v_max is null then
    return new;
  end if;
  -- Aynı siteye aynı anda gelen eklemeler sıraya girer
  perform pg_advisory_xact_lock(hashtext('birim-sinir-' || new.site_id::text));
  select count(*) into v_count from public.units where site_id = new.site_id;
  if v_count >= v_max then
    raise exception 'Bu paket en fazla % birime izin veriyor.', v_max using errcode = 'SD002';
  end if;
  return new;
end;
$$;
revoke execute on function public.enforce_unit_limit() from public, anon, authenticated;
create trigger unit_limit before insert on public.units for each row execute function public.enforce_unit_limit();

-- Kullanıcı sınırı (yeni üyelik veya yeniden etkinleşen üyelik)
create function public.enforce_user_limit()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_package text;
  v_max integer;
  v_count integer;
begin
  if new.role not in ('yonetici', 'danisma') or new.ended_on is not null then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.ended_on is null and old.role in ('yonetici', 'danisma') and old.site_id = new.site_id then
    return new; -- zaten sayılan bir üyelik
  end if;
  select package into v_package from public.sites where id = new.site_id;
  v_max := public.package_max_users(v_package);
  if v_max is null then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtext('kullanici-sinir-' || new.site_id::text));
  select count(*) into v_count from public.memberships
  where site_id = new.site_id and role in ('yonetici', 'danisma') and ended_on is null and id <> new.id;
  if v_count >= v_max then
    raise exception 'Bu paket en fazla % kullanıcıya izin veriyor.', v_max using errcode = 'SD002';
  end if;
  return new;
end;
$$;
revoke execute on function public.enforce_user_limit() from public, anon, authenticated;
create trigger user_limit before insert or update on public.memberships for each row execute function public.enforce_user_limit();

-- Paket değişikliği: sınırın üstündeki site küçük pakete düşürülemez
create function public.enforce_package_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_units integer;
  v_users integer;
begin
  if new.package is not distinct from old.package then
    return new;
  end if;
  select count(*) into v_units from public.units where site_id = new.id;
  v_users := public.site_user_count(new.id);
  if public.package_max_units(new.package) is not null and v_units > public.package_max_units(new.package) then
    raise exception 'Bu sitede % birim var; % paketi en fazla % birime izin veriyor.',
      v_units, public.package_label(new.package), public.package_max_units(new.package) using errcode = 'SD002';
  end if;
  if public.package_max_users(new.package) is not null and v_users > public.package_max_users(new.package) then
    raise exception 'Bu sitede % kullanıcı var; % paketi en fazla % kullanıcıya izin veriyor.',
      v_users, public.package_label(new.package), public.package_max_users(new.package) using errcode = 'SD002';
  end if;
  return new;
end;
$$;
revoke execute on function public.enforce_package_change() from public, anon, authenticated;
create trigger package_change before update of package on public.sites for each row execute function public.enforce_package_change();
