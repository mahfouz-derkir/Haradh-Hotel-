-- الصق هذا الملف كاملاً في Supabase > SQL Editor ثم اضغط Run
create table if not exists public.site_state (
  id int primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz default now()
);
insert into public.site_state (id, data) values (1, '{}'::jsonb) on conflict (id) do nothing;

alter table public.site_state enable row level security;

-- الجميع يقرأ
create policy "public read" on public.site_state for select using (true);
-- فقط المستخدم المسجّل (الإدارة) يعدّل
create policy "admin update" on public.site_state for update to authenticated using (true) with check (true);
