# Doctor Portal (Vercel-ready static app)

## What this portal now does
- Doctor login + create-account with **full name, email, password**.
- New doctor accounts are tagged with role metadata `doctor`.
- Doctors can search a patient directory by **name/email/UUID**.
- Doctors can assign and unassign patients in-app.
- Doctors open dashboards only for assigned patients.

## Important architecture note
Do **not** add custom columns directly to `auth.users` unless absolutely required.
Use a public `profiles` table for app-level fields (name, role, etc.) and keep Auth as identity-only.

This repo includes `webAppTest/sql/doctor_portal_setup.sql` to create:
- `public.profiles` (`user_id`, `full_name`, `email`, `role`)
- `public.doctor_patients` mapping table
- RLS policies so doctors can read patient profiles and manage their own assignments
- an `auth.users` trigger that auto-creates/syncs profile rows on signup.

## Dummy CSV data for Supabase import
CSV files are in `webAppTest/data`:
- `profiles_dummy.csv`
- `doctor_patients_dummy.csv`
- `baseline_dummy.csv`
- `pinch_dummy.csv`
- `grip_dummy.csv`
- `flexion_dummy.csv`

### Import order
1. Run `webAppTest/sql/doctor_portal_setup.sql` once in Supabase SQL Editor.
2. Create real auth users first (UUIDs must exist in `auth.users`).
3. Update CSV UUIDs to match your real users.
4. Import `profiles_dummy.csv` (optional if trigger already creates them).
5. Import `doctor_patients_dummy.csv`.
6. Import baseline/pinch/grip/flexion CSVs.

## Deploy on Vercel
1. Import this repository in Vercel.
2. Set project root to `webAppTest`.
3. Framework preset: **Other**.
4. Build command: *(leave empty)*.
5. Output directory: `.`
