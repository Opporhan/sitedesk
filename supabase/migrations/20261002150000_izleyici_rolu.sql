-- Salt okunur demo hesabı için "izleyici" rolü (sadece okur; hiçbir yazma kuralında yoktur)
set local lock_timeout = '15s';
set local statement_timeout = '60s';
alter type public.site_role add value if not exists 'izleyici';
