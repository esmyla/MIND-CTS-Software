# Data Schema (Supabase)

Owner-scoped schema for Baseline, Pinch, Grip, and Flexion data. Every row belongs to the signed-in user (FK to `auth.users.id`). Row-Level Security (RLS) only allows users to read/write their own rows.

---

## Quick Start

1. Paste the **DDL** and **RLS policies** below into Supabase SQL editor and run.
2. Use the **Client Usage** examples to insert/query. `user_id` defaults to `auth.uid()`.
3. Verify RLS with the **Testing** steps.

---

## Schema Summary

```
public.baseline (1 row typical per user)
  id PK, user_id → auth.users.id, base_it, base_mt, base_grip, base_flex_deg, base_rep_count, created_at

public.pinch (per-session pinch)
  id PK, user_id → auth.users.id, session_id, it, mt, r_it, r_mt, created_at

public.grip (per-session grip)
  id PK, user_id → auth.users.id, session_id, fsr_palm, r_fsr_palm, created_at

public.flexion (per-session ROM workload)
  id PK, user_id → auth.users.id, session_id, degree, repetitions, level_up, created_at
```

Key conventions:

* `user_id` maps to Supabase OAuth user (`auth.users.id`).
* `r_*` columns are ratios vs. the user’s baseline.
* Timestamps are `timestamptz` with `now()` default.

---

## Table Specs

### 1) `public.baseline`

Purpose: baseline metrics per user.

| column         | type                 | notes                                       |
| -------------- | -------------------- | ------------------------------------------- |
| id             | bigserial PK         | row id                                      |
| user_id        | uuid NOT NULL        | FK → `auth.users(id)`, default `auth.uid()` |
| base_it        | double precision     | baseline index–thumb pinch force            |
| base_mt        | double precision     | baseline middle–thumb pinch force           |
| base_grip      | double precision     | baseline palm grip force                    |
| base_flex_deg  | integer              | baseline hand/wrist flexion angle (degrees) |
| base_rep_count | integer              | baseline max reps at `base_flex_deg`        |
| created_at     | timestamptz NOT NULL | default `now()`                             |

Index: `(user_id)`

---

### 2) `public.pinch`

Purpose: per-session pinch measurements and ratios.

| column     | type                 | notes                                       |
| ---------- | -------------------- | ------------------------------------------- |
| id         | bigserial PK         |                                             |
| user_id    | uuid NOT NULL        | FK → `auth.users(id)`, default `auth.uid()` |
| session_id | bigint               | app/run identifier                          |
| it         | double precision     | index–thumb pinch force                     |
| mt         | double precision     | middle–thumb pinch force                    |
| r_it       | double precision     | ratio `it / baseline.base_it`               |
| r_mt       | double precision     | ratio `mt / baseline.base_mt`               |
| created_at | timestamptz NOT NULL | default `now()`                             |

Index: `(user_id, session_id)`

---

### 3) `public.grip`

Purpose: per-session palm grip and ratio.

| column     | type                 | notes                                       |
| ---------- | -------------------- | ------------------------------------------- |
| id         | bigserial PK         |                                             |
| user_id    | uuid NOT NULL        | FK → `auth.users(id)`, default `auth.uid()` |
| session_id | bigint               | app/run identifier                          |
| fsr_palm   | double precision     | palm grip force (palm FSR)                  |
| r_fsr_palm | double precision     | ratio `fsr_palm / baseline.base_grip`       |
| created_at | timestamptz NOT NULL | default `now()`                             |

Index: `(user_id, session_id)`

---

### 4) `public.flexion`

Purpose: per-session range-of-motion workload at a target flexion.

| column      | type                 | notes                                       |
| ----------- | -------------------- | ------------------------------------------- |
| id          | bigserial PK         |                                             |
| user_id     | uuid NOT NULL        | FK → `auth.users(id)`, default `auth.uid()` |
| session_id  | bigint               | app/run identifier                          |
| degree      | integer              | target flexion angle (degrees)              |
| repetitions | integer              | reps completed at `degree`                  |
| level_up    | boolean              | whether to advance protocol next session    |
| created_at  | timestamptz NOT NULL | default `now()`                             |

Index: `(user_id, session_id)`

> Note: `curr_flex` and `curr_rep_count` were removed as redundant with `degree`, `repetitions`, and `level_up`.

---

## SQL: Create Tables (DDL)

```sql
-- BASELINE
create table if not exists public.baseline (
  id             bigserial primary key,
  user_id        uuid not null default auth.uid()
                   references auth.users(id) on delete cascade,
  base_it        double precision,
  base_mt        double precision,
  base_grip      double precision,
  base_flex_deg  integer,
  base_rep_count integer,
  created_at     timestamptz not null default now()
);
create index if not exists baseline_user_idx on public.baseline (user_id);

-- PINCH
create table if not exists public.pinch (
  id         bigserial primary key,
  user_id    uuid not null default auth.uid()
               references auth.users(id) on delete cascade,
  session_id bigint,
  it         double precision,
  mt         double precision,
  r_it       double precision,
  r_mt       double precision,
  created_at timestamptz not null default now()
);
create index if not exists pinch_user_idx on public.pinch (user_id, session_id);

-- GRIP
create table if not exists public.grip (
  id         bigserial primary key,
  user_id    uuid not null default auth.uid()
               references auth.users(id) on delete cascade,
  session_id bigint,
  fsr_palm   double precision,
  r_fsr_palm double precision,
  created_at timestamptz not null default now()
);
create index if not exists grip_user_idx on public.grip (user_id, session_id);

-- FLEXION
create table if not exists public.flexion (
  id           bigserial primary key,
  user_id      uuid not null default auth.uid()
                 references auth.users(id) on delete cascade,
  session_id   bigint,
  degree       integer,
  repetitions  integer,
  level_up     boolean,
  created_at   timestamptz not null default now()
);
create index if not exists flexion_user_idx on public.flexion (user_id, session_id);
```

---

## Row-Level Security (RLS)

Enable RLS on all tables:

```sql
alter table public.baseline enable row level security;
alter table public.pinch   enable row level security;
alter table public.grip    enable row level security;
alter table public.flexion enable row level security;
```

Policies for each table (copy block per table):

```sql
-- ===== baseline =====
create policy baseline_select_own
  on public.baseline for select
  using (auth.uid() = user_id);

create policy baseline_insert_own
  on public.baseline for insert
  with check (auth.uid() = user_id);

create policy baseline_update_own
  on public.baseline for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy baseline_delete_own
  on public.baseline for delete
  using (auth.uid() = user_id);

-- ===== pinch =====
create policy pinch_select_own
  on public.pinch for select
  using (auth.uid() = user_id);

create policy pinch_insert_own
  on public.pinch for insert
  with check (auth.uid() = user_id);

create policy pinch_update_own
  on public.pinch for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy pinch_delete_own
  on public.pinch for delete
  using (auth.uid() = user_id);

-- ===== grip =====
create policy grip_select_own
  on public.grip for select
  using (auth.uid() = user_id);

create policy grip_insert_own
  on public.grip for insert
  with check (auth.uid() = user_id);

create policy grip_update_own
  on public.grip for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy grip_delete_own
  on public.grip for delete
  using (auth.uid() = user_id);

-- ===== flexion =====
create policy flexion_select_own
  on public.flexion for select
  using (auth.uid() = user_id);

create policy flexion_insert_own
  on public.flexion for insert
  with check (auth.uid() = user_id);

create policy flexion_update_own
  on public.flexion for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy flexion_delete_own
  on public.flexion for delete
  using (auth.uid() = user_id);
```

Optional: generate all policies in one block:

```sql
do $$
declare t text;
begin
  foreach t in array array['baseline','pinch','grip','flexion'] loop
    execute format('create policy %I_select_own on public.%I for select using (auth.uid() = user_id);', t, t);
    execute format('create policy %I_insert_own on public.%I for insert with check (auth.uid() = user_id);', t, t);
    execute format('create policy %I_update_own on public.%I for update using (auth.uid() = user_id) with check (auth.uid() = user_id);', t, t);
    execute format('create policy %I_delete_own on public.%I for delete using (auth.uid() = user_id);', t, t);
  end loop;
end $$;
```

---

## Client Usage (supabase-js)

Inserts (no `user_id` needed):

```ts
await supabase.from('baseline').insert({
  base_it: 0.40, base_mt: 1.05, base_grip: 22.3, base_flex_deg: 45, base_rep_count: 10
});

await supabase.from('pinch').insert({
  session_id: 1, it: 0.42, mt: 1.10, r_it: 0.42/0.40, r_mt: 1.10/1.05
});

await supabase.from('grip').insert({
  session_id: 1, fsr_palm: 0.72, r_fsr_palm: 0.72/22.3
});

await supabase.from('flexion').insert({
  session_id: 1, degree: 30, repetitions: 10, level_up: false
});
```

Queries (RLS restricts to caller):

```ts
const { data: pinch } = await supabase
  .from('pinch')
  .select('*')
  .eq('session_id', 1)
  .order('created_at', { ascending: false });
```

---

## Testing RLS

1. With a signed-in user, insert a row into each table.
2. Sign out, sign in as a different user; confirm that queries return **no rows**.
3. Using the SQL editor (service role bypasses RLS), run `select * from public.pinch;` to verify rows exist for multiple users.

---

## Notes & Options

* Units: define N vs. raw FSR counts; angles in degrees.
* Delete behavior: `on delete cascade` removes a user’s rows when the user is deleted. To keep data, switch to `on delete set null` and make `user_id` nullable (and adjust policies).
* Indexes provided optimize per-user and per-session queries.
* Ratios (`r_*`) can be computed client-side or via a view; keep null if baseline missing.
