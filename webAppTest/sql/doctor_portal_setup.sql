-- Run this once in Supabase SQL Editor.
-- Creates a public profile directory + doctor->patient assignment mapping.
-- Does NOT alter or remove any existing rehab table columns.

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text,
  role text not null default 'patient' check (role in ('doctor', 'patient')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.doctor_patients (
  id bigint generated always as identity primary key,
  doctor_id uuid not null references auth.users(id) on delete cascade,
  patient_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (doctor_id, patient_id)
);

alter table public.profiles enable row level security;
alter table public.doctor_patients enable row level security;

-- Profiles policies.
drop policy if exists "profiles self read" on public.profiles;
create policy "profiles self read"
on public.profiles for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "profiles self upsert" on public.profiles;
create policy "profiles self upsert"
on public.profiles for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "profiles self update" on public.profiles;
create policy "profiles self update"
on public.profiles for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- Doctor can read all patient profiles by name for search.
drop policy if exists "doctor read patient profiles" on public.profiles;
create policy "doctor read patient profiles"
on public.profiles for select
to authenticated
using (
  role = 'patient'
  and exists (
    select 1
    from public.profiles as p
    where p.user_id = auth.uid()
      and p.role = 'doctor'
  )
);

-- Doctor assignment policies.
drop policy if exists "doctor read assignments" on public.doctor_patients;
create policy "doctor read assignments"
on public.doctor_patients for select
to authenticated
using (doctor_id = auth.uid());

drop policy if exists "doctor create assignments" on public.doctor_patients;
create policy "doctor create assignments"
on public.doctor_patients for insert
to authenticated
with check (doctor_id = auth.uid());

drop policy if exists "doctor delete assignments" on public.doctor_patients;
create policy "doctor delete assignments"
on public.doctor_patients for delete
to authenticated
using (doctor_id = auth.uid());

-- Optional helper to keep updated_at fresh.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_profiles_touch_updated_at on public.profiles;
create trigger trg_profiles_touch_updated_at
before update on public.profiles
for each row execute function public.touch_updated_at();
