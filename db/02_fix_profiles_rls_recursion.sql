-- Fix infinite recursion in the `profiles` row-level security policies.
--
-- PROBLEM
-- Every query against public.profiles currently fails with:
--
--     42P17: infinite recursion detected in policy for relation "profiles"
--
-- The "doctor read patient profiles" policy in doctor_portal_setup.sql is a
-- policy ON profiles whose USING clause SELECTs FROM profiles:
--
--     using (
--       role = 'patient'
--       and exists (select 1 from public.profiles as p
--                   where p.user_id = auth.uid() and p.role = 'doctor')
--     )
--
-- Evaluating that inner SELECT re-applies the same policy, which evaluates the
-- inner SELECT again, and so on. Postgres detects the cycle and aborts. The
-- result is that the doctor portal cannot read any profile at all — not even
-- the signed-in doctor's own row, because policies are OR-ed together and the
-- broken one is evaluated regardless.
--
-- FIX
-- Move the role lookup into a SECURITY DEFINER function. It runs as its owner
-- rather than the caller, so the inner read does not re-enter the policy and
-- the cycle is broken.
--
-- Run once in: Supabase dashboard -> SQL Editor. Safe to re-run.

-- ---------------------------------------------------------------------------
-- Role lookup that does not re-enter RLS
-- ---------------------------------------------------------------------------

create or replace function public.is_doctor(uid uuid)
returns boolean
language sql
stable
security definer
-- Pin search_path: a SECURITY DEFINER function without this can be hijacked by
-- a caller-controlled search_path resolving `profiles` to their own table.
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where user_id = uid
      and role = 'doctor'
  );
$$;

-- The function reads profiles on the caller's behalf, so expose it narrowly.
revoke all on function public.is_doctor(uuid) from public;
grant execute on function public.is_doctor(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Replace the recursive policy
-- ---------------------------------------------------------------------------

drop policy if exists "doctor read patient profiles" on public.profiles;
create policy "doctor read patient profiles"
on public.profiles for select
to authenticated
using (
  role = 'patient'
  and public.is_doctor(auth.uid())
);

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- Should return rows rather than raising 42P17. Run while signed in as a
-- doctor to also confirm patient rows are visible.

select user_id, full_name, email, role
from public.profiles
limit 5;
