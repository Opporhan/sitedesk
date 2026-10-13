-- Uygulamanın sahibini sistem yöneticisi yapar. Bir kez çalıştırılır; e-posta adresini kendi adresinizle değiştirin.
insert into public.platform_admins (user_id)
select id from auth.users where email = 'sizin-adresiniz@example.com'
on conflict do nothing;

-- Kontrol: 1 satır görünmeli
select u.email, 'Sistem yöneticisi' as rol
from public.platform_admins p join auth.users u on u.id = p.user_id;
