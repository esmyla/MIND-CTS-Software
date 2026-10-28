-- Clinician notes on a patient.
--
-- The dashboard shows what the sensors measured. It has nowhere to record what
-- the clinician concluded — "grip plateaued, suspect splint non-compliance",
-- "discharge candidate at next review" — so that context lives in someone's
-- memory or a separate system and is lost between appointments.
--
-- Run once in: Supabase dashboard -> SQL Editor. Safe to re-run.
-- Requires 01 (doctor_patients) and 03 (is_my_patient).

create table if not exists public.patient_notes (
  id         bigserial primary key,
  doctor_id  uuid not null default auth.uid()
               references auth.users(id) on delete cascade,
  patient_id uuid not null
               references auth.users(id) on delete cascade,
  body       text not null check (length(trim(body)) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists patient_notes_patient_idx
  on public.patient_notes (patient_id, created_at desc);

alter table public.patient_notes enable row level security;

-- ---------------------------------------------------------------------------
-- Who can see a note
-- ---------------------------------------------------------------------------
-- Author-only, and only for a patient still assigned to them. Two deliberate
-- consequences:
--
--   * A doctor cannot read a colleague's notes on a shared patient. Safer
--     default for a student project than silently pooling clinical opinion
--     across clinicians who have not agreed to share it.
--
--   * The PATIENT cannot read notes about themselves. That is the
--     conventional default for clinical working notes, but it is a policy
--     choice, not a technical one — several jurisdictions give patients a
--     right of access to their records. Revisit before this is used with real
--     patients rather than assuming this default is correct.

drop policy if exists "author reads own notes" on public.patient_notes;
create policy "author reads own notes"
on public.patient_notes for select
to authenticated
using (doctor_id = auth.uid() and public.is_my_patient(patient_id));

drop policy if exists "author writes own notes" on public.patient_notes;
create policy "author writes own notes"
on public.patient_notes for insert
to authenticated
with check (doctor_id = auth.uid() and public.is_my_patient(patient_id));

drop policy if exists "author edits own notes" on public.patient_notes;
create policy "author edits own notes"
on public.patient_notes for update
to authenticated
using (doctor_id = auth.uid())
with check (doctor_id = auth.uid());

drop policy if exists "author deletes own notes" on public.patient_notes;
create policy "author deletes own notes"
on public.patient_notes for delete
to authenticated
using (doctor_id = auth.uid());

-- Keep updated_at honest. touch_updated_at() comes from 01.
drop trigger if exists trg_patient_notes_touch on public.patient_notes;
create trigger trg_patient_notes_touch
before update on public.patient_notes
for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
select count(*) as visible_notes from public.patient_notes;
