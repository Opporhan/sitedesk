-- Bütçe notları (işletme projesinin altındaki açıklamalar) ve grup adı düzenleme
alter table public.budgets add column notes text;
grant update (notes) on public.budgets to authenticated;
grant update (group_code) on public.budget_items to authenticated;
