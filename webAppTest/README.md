# Doctor Portal (Vercel-ready static app)

## What was added
- Supabase email/password auth login + account creation.
- Patient selection view sourced from `baseline`, `pinch`, `grip`, and `flexion` tables.
- Per-patient dashboard with KPI cards, trend graphs, and activity log.

## Deploy on Vercel
1. Import this repository in Vercel.
2. Set project root to `webAppTest`.
3. Framework preset: **Other**.
4. Build command: *(leave empty)*.
5. Output directory: `.`

The app currently uses the provided Supabase URL + anon key in `supabase.js`.
