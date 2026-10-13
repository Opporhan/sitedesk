-- Faz 2: Bakım ve sözleşme takvimi
-- Her iş belirli aralıkla tekrarlanır (asansör aylık bakımı, yıllık kontrol, sigorta yenileme…).
-- "Yapıldı" denince geçmişe kayıt düşer ve bir sonraki tarih = yapıldığı gün + aralık olur.
-- İşler silinmez, kaldırılır (geçmiş kalır).

create table public.maintenance_tasks (
  id uuid primary key default gen_random_uuid(),
  site_id uuid not null references public.sites (id) on delete restrict,
  name text not null check (length(trim(name)) between 2 and 120),
  interval_months smallint not null check (interval_months between 1 and 120),
  next_due date not null,
  vendor text check (vendor is null or length(vendor) <= 120),
  vendor_phone text check (vendor_phone is null or vendor_phone ~ '^90[0-9]{10}$'),
  note text check (note is null or length(note) <= 500),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  unique (id, site_id)
);

create index on public.maintenance_tasks (site_id, next_due) where active;

create table public.maintenance_logs (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null,
  site_id uuid not null,
  done_on date not null,
  note text check (note is null or length(note) <= 500),
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  foreign key (task_id, site_id) references public.maintenance_tasks (id, site_id) on delete restrict
);

create index on public.maintenance_logs (task_id, done_on desc);

revoke all on public.maintenance_tasks, public.maintenance_logs from anon, authenticated;
grant select, insert on public.maintenance_tasks to authenticated;
grant update (name, interval_months, next_due, vendor, vendor_phone, note, active) on public.maintenance_tasks to authenticated;
grant select on public.maintenance_logs to authenticated;
alter table public.maintenance_tasks enable row level security;
alter table public.maintenance_logs enable row level security;

create policy "bakım işi görme" on public.maintenance_tasks
  for select to authenticated using (public.has_site_role(site_id, '{yonetici}'));
create policy "bakım işi ekleme" on public.maintenance_tasks
  for insert to authenticated with check (public.has_site_role(site_id, '{yonetici}'));
create policy "bakım işi düzenleme" on public.maintenance_tasks
  for update to authenticated
  using (public.has_site_role(site_id, '{yonetici}'))
  with check (public.has_site_role(site_id, '{yonetici}'));
create policy "bakım geçmişi görme" on public.maintenance_logs
  for select to authenticated using (public.has_site_role(site_id, '{yonetici}'));

-- "Yapıldı": geçmişe yazar, bir sonraki tarihi ileri alır (geçmiş kayıt sadece bu fonksiyonla girilir)
create function public.complete_maintenance(p_task_id uuid, p_done_on date, p_note text)
returns date
language plpgsql security definer set search_path = ''
as $$
declare
  v_task public.maintenance_tasks;
  v_next date;
begin
  select * into v_task from public.maintenance_tasks where id = p_task_id;
  if v_task.id is null or not public.has_site_role(v_task.site_id, '{yonetici}') then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if not v_task.active then
    raise exception 'Bu iş kaldırılmış' using errcode = '22023';
  end if;
  if p_done_on is null or p_done_on > (now() at time zone 'Europe/Istanbul')::date then
    raise exception 'İleri tarih girilemez' using errcode = '22023';
  end if;

  insert into public.maintenance_logs (task_id, site_id, done_on, note)
  values (v_task.id, v_task.site_id, p_done_on, nullif(trim(p_note), ''));

  v_next := (p_done_on + make_interval(months => v_task.interval_months))::date;
  update public.maintenance_tasks set next_due = v_next where id = v_task.id;
  return v_next;
end;
$$;

revoke execute on function public.complete_maintenance(uuid, date, text) from public, anon;
grant execute on function public.complete_maintenance(uuid, date, text) to authenticated;
