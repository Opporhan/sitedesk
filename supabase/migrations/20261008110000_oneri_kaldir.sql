-- "Öneri" türü kaldırıldı (kullanıcı kararı 08.10.2026: talep ile aynı iş). Var olan öneri kayıtları "talep" olur
-- (sadece demo sitesinde 1 kayıt vardı). Kalan türler: arıza, talep, şikâyet.
set local lock_timeout = '15s';
set local statement_timeout = '60s';

update public.tickets set kind = 'talep' where kind = 'oneri';
alter table public.tickets drop constraint tickets_kind_check;
alter table public.tickets add constraint tickets_kind_check check (kind in ('ariza', 'talep', 'sikayet'));

-- Yeni kayıt bildirimi: tür adları (öneri yok)
create or replace function public.notify_ticket_created()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_kind text := case new.kind when 'ariza' then 'arıza' when 'talep' then 'talep' else 'şikâyet' end;
begin
  perform public.notify_users(public.site_manager_users(new.site_id),
    case when new.urgent then '🔴 ACİL · ' || public.unit_label(new.unit_id) else 'Yeni ' || v_kind || ' · ' || public.unit_label(new.unit_id) end,
    new.title, '/kayit/' || new.id);
  return new;
end;
$$;
