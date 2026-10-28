-- Exercise adherence, and the heart-rate data behind the strength+exertion
-- metric in Research/SoftwareGoals.md.
--
-- Two gaps this closes:
--
--   1. PT exercise completions lived only in the patient's browser storage, so
--      they were lost on a cache clear, never synced between devices, and were
--      invisible to the clinician — who is the person who most needs to know
--      whether the prescribed exercises were actually done.
--
--   2. The glove streams heart rate and the app displayed it live, but nothing
--      ever stored it. Phase 4 of the project goals — combining strength with
--      physiological exertion into one recovery measure — had no data to work
--      from.
--
-- Run once in: Supabase dashboard -> SQL Editor. Safe to re-run.
-- Run AFTER 01-03.

-- ---------------------------------------------------------------------------
-- 1. Exercise adherence
-- ---------------------------------------------------------------------------

create table if not exists public.pt_sessions (
  id           bigserial primary key,
  user_id      uuid not null default auth.uid()
                 references auth.users(id) on delete cascade,
  -- Matches Exercise.id in patient-app/lib/features/pt_tracking/data/pt_exercises.dart
  -- ('tendon_glide', 'median_nerve_glide', ...). Deliberately text, not an
  -- enum: the library changes with clinical review, and a migration per new
  -- exercise would be friction in exactly the wrong place.
  exercise_id  text not null,
  -- False when the patient tapped "mark done and finish" early rather than
  -- working through every rep. Worth distinguishing: partial adherence is a
  -- different clinical signal from none.
  completed    boolean not null default true,
  completed_at timestamptz not null default now(),
  -- The patient's LOCAL calendar day, supplied by the app.
  --
  -- A plain column rather than an index on (completed_at::date), for two
  -- reasons. Postgres refuses that expression in an index because casting
  -- timestamptz to date depends on the session TimeZone and so is not
  -- IMMUTABLE. And it would be the wrong day anyway: adherence is a human
  -- notion of "today", so a patient exercising at 11pm would have it counted
  -- against tomorrow under UTC.
  completed_on date not null default ((now() at time zone 'utc')::date)
);

-- One row per exercise per day. Repeating an exercise the same day is normal
-- and should not inflate the count, so the insert upserts onto this.
create unique index if not exists pt_sessions_user_exercise_day
  on public.pt_sessions (user_id, exercise_id, completed_on);

create index if not exists pt_sessions_user_idx
  on public.pt_sessions (user_id, completed_on desc);

alter table public.pt_sessions enable row level security;

drop policy if exists "pt own read" on public.pt_sessions;
create policy "pt own read"
on public.pt_sessions for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "pt own insert" on public.pt_sessions;
create policy "pt own insert"
on public.pt_sessions for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "pt own update" on public.pt_sessions;
create policy "pt own update"
on public.pt_sessions for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- The clinician needs this more than anyone. Read-only: a doctor reviews
-- adherence, they never record it on the patient's behalf.
-- Requires is_my_patient() from 03_doctor_read_patient_data.sql.
drop policy if exists "doctor reads assigned pt_sessions" on public.pt_sessions;
create policy "doctor reads assigned pt_sessions"
on public.pt_sessions for select
to authenticated
using (public.is_my_patient(user_id));

-- ---------------------------------------------------------------------------
-- 2. Heart rate on strength sessions
-- ---------------------------------------------------------------------------
-- Stored on the session rows rather than in their own table: heart rate is
-- measured during the hold, by the same glove, in the same five seconds. It is
-- an attribute of that measurement, not an independent time series.
--
-- Nullable throughout. The MAX30102 only reports a usable rate when a finger is
-- on the sensor (the firmware zeroes it otherwise), so a perfectly valid grip
-- session can have no heart rate at all. Writing 0 would read as bradycardia.

alter table public.grip  add column if not exists bpm_avg  integer;
alter table public.grip  add column if not exists bpm_peak integer;
alter table public.pinch add column if not exists bpm_avg  integer;
alter table public.pinch add column if not exists bpm_peak integer;

-- Resting heart rate, so exertion can be expressed relative to the patient
-- rather than to a population average.
alter table public.baseline add column if not exists base_bpm_rest integer;

comment on column public.grip.bpm_avg is
  'Mean heart rate during the hold. Null when no finger was on the sensor.';
comment on column public.baseline.base_bpm_rest is
  'Resting heart rate, captured before the first hold. Denominator for exertion.';

-- ---------------------------------------------------------------------------
-- Why there is no stored "recovery score"
-- ---------------------------------------------------------------------------
-- The combined strength+exertion measure is deliberately NOT a column. Its
-- definition is still a clinical question, and a stored score computed under
-- one definition silently becomes wrong when the definition changes, with no
-- way to tell old rows from new. The inputs above are durable facts; the score
-- is derived in the app, where it can be revised without a migration and
-- without reinterpreting history.

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------

select column_name, data_type, is_nullable
from   information_schema.columns
where  table_schema = 'public'
  and  ((table_name = 'grip'     and column_name like 'bpm%')
     or (table_name = 'pinch'    and column_name like 'bpm%')
     or (table_name = 'baseline' and column_name = 'base_bpm_rest'))
order by table_name, column_name;
