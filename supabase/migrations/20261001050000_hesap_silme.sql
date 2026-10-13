-- Bir kullanıcı hesabı silinince kayıtlar silinmesin ve silmeyi engellemesin:
-- "oluşturan" (created_by) ve "iptal eden" (cancelled_by) bilgileri boşalır, kayıt yerinde kalır.
do $$
declare r record;
begin
  for r in
    select c.conrelid::regclass as tbl, c.conname, a.attname as col
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
    where c.contype = 'f'
      and c.confrelid = 'auth.users'::regclass
      and c.connamespace = 'public'::regnamespace
      and a.attname in ('created_by', 'cancelled_by')
  loop
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
    execute format('alter table %s add constraint %I foreign key (%I) references auth.users (id) on delete set null', r.tbl, r.conname, r.col);
  end loop;
end $$;
