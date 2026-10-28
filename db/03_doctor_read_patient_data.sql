-- Let a doctor read the rehab data of patients assigned to them.
--
-- PROBLEM
-- The doctor dashboard queries baseline / pinch / grip / flexion filtered by a
-- patient's user_id, but the only SELECT policy on those tables is
-- `user_id = auth.uid()`. A doctor is not the patient, so every one of those
-- queries returns an empty array and the dashboard renders with no KPIs, empty
-- charts and "No activity recorded for this patient."
--
-- Nothing errors. It just silently shows nothing, which is why this was easy to
-- miss: the portal looks like it works until you open a patient who definitely
-- has sessions.
--
-- FIX
-- Add a second SELECT policy per table, granting access when the row's owner is
-- assigned to the requesting doctor. Policies are OR-ed, so patients keep their
-- own access exactly as before and nothing else widens.
--
-- Run once in: Supabase dashboard -> SQL Editor. Safe to re-run.
-- Requires doctor_portal_setup.sql (for doctor_patients) to have been run first.

-- ---------------------------------------------------------------------------
-- Assignment lookup that does not depend on the caller's own RLS
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER for the same reason as is_doctor(): the check runs as the
-- function's owner, so it reads doctor_patients directly instead of through the
-- caller's policies. search_path is pinned, since a SECURITY DEFINER function
-- without that can be hijacked by a caller-controlled search_path.

create or replace function public.is_my_patient(patient uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.doctor_patients
    where doctor_id = auth.uid()
      and patient_id = patient
  );
$$;

revoke all on function public.is_my_patient(uuid) from public;
grant execute on function public.is_my_patient(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Read policies, one per rehab table
-- ---------------------------------------------------------------------------
-- SELECT only. A doctor reviews data; they never write a patient's session, and
-- granting insert or update here would let the portal fabricate clinical
-- records.

drop policy if exists "doctor reads assigned baseline" on public.baseline;
create policy "doctor reads assigned baseline"
on public.baseline for select
to authenticated
using (public.is_my_patient(user_id));

drop policy if exists "doctor reads assigned flexion" on public.flexion;
create policy "doctor reads assigned flexion"
on public.flexion for select
to authenticated
using (public.is_my_patient(user_id));

drop policy if exists "doctor reads assigned grip" on public.grip;
create policy "doctor reads assigned grip"
on public.grip for select
to authenticated
using (public.is_my_patient(user_id));

drop policy if exists "doctor reads assigned pinch" on public.pinch;
create policy "doctor reads assigned pinch"
on public.pinch for select
to authenticated
using (public.is_my_patient(user_id));

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- Signed in as a doctor who has at least one assigned patient, this should
-- return that patient's rows. Signed in as a doctor with no assignments, it
-- should return nothing — which is the point.

select 'flexion' as source, count(*) from public.flexion
union all select 'grip',     count(*) from public.grip
union all select 'pinch',    count(*) from public.pinch
union all select 'baseline', count(*) from public.baseline;
