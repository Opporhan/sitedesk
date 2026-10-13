-- Faz 2: İşlem geçmişi — para ile ilgili her değişiklik kim, ne zaman, ne yaptı
-- Kayıtları uygulama değil veritabanı tetikleyicileri yazar (hiçbir ekran atlayamaz).
-- Geçmiş değiştirilemez ve silinemez. Ayın 1'indeki otomatik aidat yazımı kaydedilmez (gürültü);
-- elle "Şimdi yaz" kaydedilir.

create table public.audit_log (
  id bigint generated always as identity primary key,
  site_id uuid not null references public.sites (id) on delete restrict,
  at timestamptz not null default now(),
  actor_id uuid references auth.users (id) on delete set null,
  actor_name text, -- o anki ad (hesap silinse de görünsün)
  entity text not null,
  action text not null check (action in ('ekle', 'degistir', 'iptal', 'sil')),
  record_id uuid,
  old_data jsonb,
  new_data jsonb
);

create index on public.audit_log (site_id, at desc);
create index on public.audit_log (record_id);

revoke all on public.audit_log from anon, authenticated;
grant select on public.audit_log to authenticated;
alter table public.audit_log enable row level security;

create policy "işlem geçmişi görme" on public.audit_log
  for select to authenticated using (public.has_site_role(site_id, '{yonetici}'));

create function public.audit_row()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_old jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  v_new jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  v_actor uuid := auth.uid();
  v_action text;
begin
  -- Otomatik aylık aidat yazımı (oturum yok) kaydedilmez
  if tg_table_name = 'dues' and tg_op = 'INSERT' and v_actor is null then
    return null;
  end if;
  if tg_op = 'UPDATE' and v_old = v_new then
    return null;
  end if;

  v_action := case
    when tg_op = 'INSERT' then 'ekle'
    when tg_op = 'DELETE' then 'sil'
    when v_new->>'status' = 'iptal' and v_old->>'status' is distinct from 'iptal' then 'iptal'
    else 'degistir'
  end;

  insert into public.audit_log (site_id, actor_id, actor_name, entity, action, record_id, old_data, new_data)
  values (
    coalesce(v_new->>'site_id', v_old->>'site_id')::uuid,
    v_actor,
    (select nullif(full_name, '') from public.profiles where user_id = v_actor),
    tg_table_name,
    v_action,
    coalesce(v_new->>'id', v_old->>'id')::uuid,
    v_old,
    v_new
  );
  return null;
end;
$$;

revoke execute on function public.audit_row() from public, anon, authenticated;

create trigger audit after insert or update or delete on public.payments for each row execute function public.audit_row();
create trigger audit after insert or update or delete on public.dues for each row execute function public.audit_row();
create trigger audit after insert or update or delete on public.cash_entries for each row execute function public.audit_row();
create trigger audit after insert or update or delete on public.unit_due_rates for each row execute function public.audit_row();
create trigger audit after insert or update or delete on public.budgets for each row execute function public.audit_row();
create trigger audit after insert or update or delete on public.budget_items for each row execute function public.audit_row();
create trigger audit after insert or update or delete on public.bank_checks for each row execute function public.audit_row();
create trigger audit after insert or update or delete on public.cash_documents for each row execute function public.audit_row();
