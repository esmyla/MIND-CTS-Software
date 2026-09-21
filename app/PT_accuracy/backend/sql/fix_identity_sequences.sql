-- Fix out-of-sync identity sequences on the rehab tables.
--
-- PROBLEM
-- The dummy CSVs in webAppTest/data were imported with explicit `id` values,
-- but importing rows this way does not advance each table's identity sequence.
-- So nextval() still returns 1, which collides with the imported row id=1 and
-- every insert fails with:
--
--     duplicate key value violates unique constraint "<table>_pkey"  (23505)
--
-- This hits a real patient on their first recorded session, and it is silent
-- from the database's point of view — the app just sees a failed write.
--
-- FIX
-- Move each sequence past the highest id currently in the table.
--
-- Run once in: Supabase dashboard -> SQL Editor.
-- Safe to re-run; setval() is idempotent for a given table state.

select setval(
  pg_get_serial_sequence('public.flexion', 'id'),
  coalesce((select max(id) from public.flexion), 0) + 1,
  false
);

select setval(
  pg_get_serial_sequence('public.grip', 'id'),
  coalesce((select max(id) from public.grip), 0) + 1,
  false
);

select setval(
  pg_get_serial_sequence('public.pinch', 'id'),
  coalesce((select max(id) from public.pinch), 0) + 1,
  false
);

-- Verify: each sequence's last_value should now exceed its table's max(id).
select
  s.sequencename,
  s.last_value,
  case s.sequencename
    when 'flexion_id_seq' then (select max(id) from public.flexion)
    when 'grip_id_seq'    then (select max(id) from public.grip)
    when 'pinch_id_seq'   then (select max(id) from public.pinch)
  end as max_id
from pg_sequences s
where s.schemaname = 'public'
  and s.sequencename in ('flexion_id_seq', 'grip_id_seq', 'pinch_id_seq');
