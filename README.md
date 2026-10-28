# CTS-Glove Project

A rehabilitation platform for **carpal tunnel syndrome**. A custom sensor glove
and a camera-based hand tracker feed one app, so therapy progress becomes
measurable instead of subjective — for the patient doing the exercises and the
clinician reviewing them.

Built by the **Purdue MIND CTS-Glove Software Team**.

---

## What's here

Every directory below is live. Nothing here is a prototype or a leftover.

| Path | What it is |
|---|---|
| [`patient-app/`](patient-app) | **Patient app** — Flutter web, five tabs. What a patient uses. |
| [`doctor-portal/`](doctor-portal) | **Doctor portal** — static HTML + Supabase. What a clinician uses. |
| [`backend/`](backend) | Two Python services both portals depend on: the camera hand-tracker and the glove sensor bridge. |
| [`db/`](db) | Everything about the database: the schema, and the numbered SQL scripts to run in order. |
| [`firmware/`](firmware) | ESP32-C6 glove firmware. `CTS_IC2.ino` is the live sketch. |
| [`brand/`](brand) | Logo master and the exports both apps use. |
| [`Research/`](Research) | Project goals and therapy references. |

**Start here:** [`RUNNING.md`](RUNNING.md) — toolchain setup and how to run the
three processes.

Earlier standalone grip and pinch prototypes, a Swift login prototype, and
several empty placeholder files were removed once the patient app's tabs
superseded them. They remain in git history.

---

## The patient app

Five tabs: **Flexion**, **FSR Grip**, **Home**, **PT Tracking**, **Pinch**.

- **Flexion** — webcam only, no glove. Frames go to the Python tracker, which
  runs MediaPipe and returns wrist angle and rep counts in real time.
- **FSR Grip / Pinch** — a guided five-second hold. The score is the mean of the
  strongest 60% of samples, and once a baseline exists each session also stores
  its ratio against it. Pinch takes index-thumb and middle-thumb as two
  sequential holds, because the current firmware exposes one FSR channel.
- **Home** — streak, session calendar, flexion trend and grip change, from
  Supabase.
- **PT Tracking** — six standard CTS exercises with a guided step timer and
  per-day adherence, stored server-side so a clinician can see it. The local
  store is kept as an offline cache, so the tab still works with no network and
  in guest mode.
- **Strength per exertion** — the glove's heart rate is recorded on each grip
  and pinch session and shown on Home as force relative to cardiovascular cost.
  This is Phase 4 of `Research/SoftwareGoals.md`. The score is computed, never
  stored: its definition is still a clinical question, and a stored score
  silently becomes wrong when the definition changes.

### Why there are two Python processes

Flutter web cannot open a serial port, and the glove is wired over USB (its BLE
is defined in firmware but not commissioned). So a bridge process owns the port
and rebroadcasts readings over a WebSocket. The camera tracker is separate
because it needs no hardware and either can run without the other.

Both are **transport only**. They never touch the database: they would have to
connect as `anon`, which row-level security rejects. All writes happen in the
app, which holds the signed-in user's JWT so RLS applies correctly.

### Glove pairing

Every patient has their own glove, so the app pairs with a specific device.
Pairing is keyed on the **USB serial number**, not the port, so a glove is still
recognised after being plugged into a different socket. Boards that report no
serial number fall back to the port, and the UI says so. The bridge
auto-attaches only when exactly one recognised board is present — with two
gloves on a bench, guessing would record the wrong patient's hand.

---

## Database

Supabase. RLS is enabled and scoped per user: a patient sees only their own
rows, and the anon key alone reads nothing.

```
flexion   id, user_id, session_id, degree_forward, degree_backwards, repetitions, level_up, created_at
grip      id, user_id, session_id, fsr_palm, r_fsr_palm, created_at
pinch     id, user_id, session_id, it, mt, r_it, r_mt, created_at
baseline  user_id, base_it, base_mt, base_grip, base_flex_deg, base_rep_count, created_at
profiles  user_id, full_name, email, role
doctor_patients  doctor_id, patient_id
```

An `r_`-prefixed column is the **ratio against that patient's baseline**, not a
raw reading. The unprefixed column is the top-60% mean.

### SQL that must be run once

| Script | Why |
|---|---|
| [`db/01_doctor_portal_setup.sql`](db/01_doctor_portal_setup.sql) | Creates `profiles` + `doctor_patients`, their policies, and the signup trigger |
| [`db/02_fix_profiles_rls_recursion.sql`](db/02_fix_profiles_rls_recursion.sql) | Fixes `42P17` infinite recursion that breaks every profile read |
| [`db/03_doctor_read_patient_data.sql`](db/03_doctor_read_patient_data.sql) | Without it a doctor's dashboard silently shows nothing — RLS hides every patient row from them |
| [`db/04_fix_identity_sequences.sql`](db/04_fix_identity_sequences.sql) | CSV imports left the id sequences behind, so a patient's first session fails |
| [`db/05_adherence_and_exertion.sql`](db/05_adherence_and_exertion.sql) | Adds `pt_sessions` and the heart-rate columns. Until it runs, exercise adherence stays local-only and heart rate is dropped from saves |

---

## Deploying

Two Vercel projects, because these are two separate sites.

**Doctor portal** — root directory `doctor-portal`, framework "Other", no build
command. Static.

**Patient app** — root directory `patient-app`. The build
fetches a pinned Flutter SDK; see [`vercel-build.sh`](patient-app/vercel-build.sh).
Set `SUPABASE_URL` and `SUPABASE_ANON_KEY` in the project's environment
variables (both are public-by-design client values, not secrets).

The Flexion, Grip and Pinch tabs need the Python processes, which require a
camera and a USB port and therefore run on the patient's own machine — not on
the web host. A deployed HTTPS page also **cannot** open an insecure `ws://`
socket; the browser blocks it. Those tabs degrade to an explanatory message on a
hosted build, and Home and PT Tracking work fully.

---

## Known issues

- A throwaway Chrome profile from `flutter run -d chrome` was committed early in
  the project's history (`.dart_tool/chrome-device/`). It is untracked now, but
  it remains in past commits and its Local Storage appears to contain a Supabase
  session. Rotating the Supabase JWT secret is what would invalidate it.
- `flutter test` cannot load `test/widget_test.dart`: it transitively imports
  `flexion_page.dart`, which uses `dart:html`, unavailable on the Dart VM where
  tests run. Fixing it means moving the browser camera code behind a conditional
  import. `test/hold_capture_test.dart` runs fine.
- `dart:html` is deprecated. It still compiles, but a `package:web` migration is
  owed, and is what the WASM dry-run warning on every build refers to.
- The glove has never been exercised end to end against this app. Everything on
  the sensor path is verified against the bridge's `--simulate` mode, so real
  ADC ranges are unconfirmed.
- Resting heart rate is captured from the patient's first grip hold, which is
  not actually a resting measurement. It is the only reading we are certain to
  have, and an approximate denominator beats no exertion measure at all, but a
  proper calibration step before the first hold would be better.
- The flexion exercise still has no baseline step, so `baseline.base_flex_deg`
  and `base_rep_count` are never written. Grip and pinch both calibrate; flexion
  does not.
