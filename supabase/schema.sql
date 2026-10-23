-- Haradh International Hotel: initial database schema
-- Run in Supabase Dashboard > SQL Editor. Review security policies before production.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  role text not null default 'staff' check (role in ('owner','manager','reception','cashier','kitchen')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create or replace function public.current_app_role()
returns text language sql stable security definer set search_path = public
as $$ select role from public.profiles where id = auth.uid() and active = true limit 1 $$;

create or replace function public.has_any_role(allowed text[])
returns boolean language sql stable security definer set search_path = public
as $$ select coalesce(public.current_app_role() = any(allowed), false) $$;

create table if not exists public.app_settings (
  id boolean primary key default true check (id),
  hotel_name text not null default 'فندق ومطعم حرض الدولي',
  currency_code text not null default 'YER',
  currency_symbol text not null default 'ر.ي',
  updated_at timestamptz not null default now()
);
insert into public.app_settings(id) values(true) on conflict do nothing;

create table if not exists public.menu_items (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  price numeric(12,2) not null default 0 check(price >= 0),
  currency_code text not null default 'YER',
  available boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  room_number text not null unique,
  room_type text not null,
  nightly_rate numeric(12,2) not null default 0 check(nightly_rate >= 0),
  currency_code text not null default 'YER',
  status text not null default 'available' check(status in ('available','occupied','maintenance','inactive')),
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  customer_name text not null,
  phone text,
  room_number text,
  details text not null,
  total numeric(12,2) not null default 0 check(total >= 0),
  currency text not null default 'YER',
  status text not null default 'new' check(status in ('new','accepted','preparing','ready','delivered','cancelled')),
  created_at timestamptz not null default now()
);

create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  customer_name text not null,
  phone text not null,
  room_type text not null,
  check_in date not null,
  check_out date not null,
  guests integer not null default 1 check(guests > 0),
  status text not null default 'pending' check(status in ('pending','confirmed','checked_in','checked_out','cancelled')),
  notes text,
  created_at timestamptz not null default now(),
  constraint valid_booking_dates check(check_out > check_in)
);

create table if not exists public.complaints (
  id uuid primary key default gen_random_uuid(),
  customer_name text,
  phone text,
  message text not null,
  status text not null default 'new' check(status in ('new','reviewing','resolved')),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.app_settings enable row level security;
alter table public.menu_items enable row level security;
alter table public.rooms enable row level security;
alter table public.orders enable row level security;
alter table public.bookings enable row level security;
alter table public.complaints enable row level security;

-- Profiles: users can see their own role; owner/manager can manage staff profiles.
create policy "profile self read" on public.profiles for select to authenticated
using (id = auth.uid() or public.has_any_role(array['owner','manager']));
create policy "owner manage profiles" on public.profiles for all to authenticated
using (public.has_any_role(array['owner'])) with check (public.has_any_role(array['owner']));

-- Public-facing catalog/settings are readable; only management edits them.
create policy "public read settings" on public.app_settings for select to anon, authenticated using (true);
create policy "management edit settings" on public.app_settings for all to authenticated
using (public.has_any_role(array['owner','manager'])) with check (public.has_any_role(array['owner','manager']));

create policy "public read available menu" on public.menu_items for select to anon, authenticated using (available = true or public.has_any_role(array['owner','manager','cashier','kitchen']));
create policy "management manage menu" on public.menu_items for all to authenticated
using (public.has_any_role(array['owner','manager'])) with check (public.has_any_role(array['owner','manager']));

create policy "staff read rooms" on public.rooms for select to authenticated
using (public.has_any_role(array['owner','manager','reception']));
create policy "management manage rooms" on public.rooms for all to authenticated
using (public.has_any_role(array['owner','manager'])) with check (public.has_any_role(array['owner','manager']));

-- Anonymous customers can submit orders/bookings/complaints. Public cannot read them.
create policy "public submit orders" on public.orders for insert to anon, authenticated
with check (status = 'new');
create policy "staff read orders" on public.orders for select to authenticated
using (public.has_any_role(array['owner','manager','cashier','kitchen']));
create policy "owner manager cashier update orders" on public.orders for update to authenticated
using (public.has_any_role(array['owner','manager','cashier','kitchen']))
with check (public.has_any_role(array['owner','manager','cashier','kitchen']));

create policy "public submit bookings" on public.bookings for insert to anon, authenticated
with check (status = 'pending');
create policy "reception read bookings" on public.bookings for select to authenticated
using (public.has_any_role(array['owner','manager','reception']));
create policy "reception update bookings" on public.bookings for update to authenticated
using (public.has_any_role(array['owner','manager','reception']))
with check (public.has_any_role(array['owner','manager','reception']));

create policy "public submit complaints" on public.complaints for insert to anon, authenticated
with check (status = 'new');
create policy "staff read complaints" on public.complaints for select to authenticated
using (public.has_any_role(array['owner','manager','reception']));
create policy "management update complaints" on public.complaints for update to authenticated
using (public.has_any_role(array['owner','manager','reception']))
with check (public.has_any_role(array['owner','manager','reception']));

-- Explicit table grants; RLS policies still decide which rows/operations are permitted.
grant select on public.app_settings to anon, authenticated;
grant select on public.menu_items to anon, authenticated;
grant insert on public.orders, public.bookings, public.complaints to anon, authenticated;
grant select, insert, update, delete on public.profiles, public.rooms, public.menu_items,
 public.app_settings, public.orders, public.bookings, public.complaints to authenticated;
