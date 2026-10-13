-- Bildirim metni: ilk durum uygulamadaki gibi "Yeni" (önce "Alındı" yazıyordu). Sadece metin değişir.
create or replace function public.notify_ticket_event()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_t public.tickets;
  v_status text := case new.status when 'alindi' then 'Yeni' when 'inceleniyor' then 'İnceleniyor' when 'yapiliyor' then 'Yapılıyor' when 'tamamlandi' then 'Tamamlandı' else new.status end;
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
