# MIND CTS — Physical Therapy Companion

Flutter web app for wrist flexion therapy with Python WebSocket backend.

---

## Project Structure

```
lib/
├── main.dart                    # Entry point — Supabase init + ProviderScope
├── app.dart                     # MaterialApp + AuthGate
├── config/
│   └── env.dart                 # All env variables & feature flags
├── routing/
│   └── app_scaffold.dart        # 5-tab bottom NavigationBar
├── shared/
│   └── widgets/
│       └── wip_page.dart        # Reusable "Work In Progress" page
└── features/
    ├── auth/
    │   ├── data/auth_repository.dart
    │   ├── state/auth_provider.dart
    │   └── presentation/login_screen.dart
    ├── home/
    │   ├── state/home_provider.dart
    │   └── presentation/home_screen.dart
    ├── flexion/
    │   ├── flexion_page.dart          # Original code (class names unchanged)
    │   └── presentation/flexion_tab.dart  # Wrapper + 5-rep popup overlay
    ├── fsr_grip/presentation/fsr_grip_page.dart
    ├── pt_tracking/presentation/pt_tracking_page.dart
    └── pinch_strength/presentation/pinch_strength_page.dart
```

---

## Environment Variables & Feature Flags

Pass these at build/run time via `--dart-define`. **Never commit secrets.**

| Variable            | Required | Default          | Description                         |
|---------------------|----------|------------------|-------------------------------------|
| `SUPABASE_URL`      | No       | `""`             | Supabase project URL                |
| `SUPABASE_ANON_KEY` | No       | `""`             | Supabase anon (public) key          |
| `WS_URL`            | No       | `ws://localhost:8765` | Python WebSocket server URL    |
| `FEATURE_AUTH`      | No       | `auto`           | `"false"` to force-disable auth     |
| `FEATURE_ANALYTICS` | No       | `false`          | Enable/disable telemetry            |
| `FEATURE_MOCK_DATA` | No       | `true`           | Use mock chart data on Home screen  |

### Behaviour when Supabase is not configured

- Auth is auto-disabled (`Env.featureAuth == false`)  
- A non-blocking banner is shown on the login screen: *"Auth disabled in this build"*  
- Guest mode is available via the **Skip** button  
- All features work locally without any network dependency

---

## Running the App

### Flutter Web (development)

```bash
# Without Supabase (guest mode only)
flutter run -d chrome --web-port 3000

# With Supabase
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGci... \
  --dart-define=WS_URL=ws://localhost:8765
```

### Python Backend

Requires Python 3.11 (not 3.14 — see compatibility note below).

```bash
cd app/PT_accuracy/backend

# Activate your 3.11 venv
.venv\Scripts\Activate.ps1        # Windows PowerShell
# source .venv/bin/activate        # macOS / Linux

python flexion_ws_server.py
```

Backend env vars:
```bash
export SUPABASE_URL=https://your-project.supabase.co
export SUPABASE_KEY=your-service-role-key
export WS_HOST=0.0.0.0
export WS_PORT=8765
export HAND_MODEL_PATH=models/hand_landmarker.task
```

---

## Tab Layout

| Index | Tab         | Content                          |
|-------|-------------|----------------------------------|
| 0     | Flexion     | Existing wrist flexion exercise  |
| 1     | FSR Grip    | Work In Progress placeholder     |
| **2** | **Home**    | **Default tab — Dashboard**      |
| 3     | PT Tracking | Work In Progress placeholder     |
| 4     | Pinch       | Work In Progress placeholder     |

---

## Auth Flow

```
App launch
  └─ Supabase session exists?
       ├─ Yes → AppScaffold (Home tab)
       └─ No  → LoginScreen
                  ├─ Sign In   → Supabase auth → AppScaffold
                  ├─ Create Account → Supabase signup → AppScaffold
                  └─ Skip      → Guest mode → AppScaffold
```

---

## Flexion 5-Rep Popup (Non-invasive)

When the Python server emits `level_up: true` (after 5 reps in one direction), 
`ExercisePage` fires the optional `onLevelUp` callback. `FlexionTab` receives 
this and shows a full-screen overlay:

- **Does not** pause sensor streaming  
- **Does not** reset rep counters (server manages that)  
- **Does not** modify direction state  
- Auto-dismisses after **3 seconds** or on tap  

---

## Python Version Compatibility

MediaPipe requires **Python 3.9–3.12**. Python 3.14 breaks `ctypes` bindings.

```powershell
# Recreate venv with Python 3.11
Remove-Item -Recurse -Force .venv
& "C:\Path\To\Python311\python.exe" -m venv .venv
.venv\Scripts\Activate.ps1
pip install opencv-python mediapipe numpy websockets supabase
```

---

## Running Tests

```bash
flutter test
```

Tests cover:
- `AuthGate` routing (unauthenticated / guest / authenticated)  
- Bottom nav tab switching  
- WipPage heading text matches spec  
- HomeScreen renders all 3 dashboard components  

---

## TODO Markers (Next Iteration)

- `TODO(home)` — Replace mock streak & chart with Supabase-backed queries once schema + RLS are confirmed  
- `TODO(fsr)` — Replace WIP page with real FSR capture + analysis when server endpoints are defined  
- `TODO(pinch)` — Replace WIP page with real pinch capture when sensor protocol is finalised  
- `TODO(pt)` — Implement therapy protocols and adherence tracking after clinical review  
- `TODO(auth)` — Wire Supabase credentials via CI/CD secrets and remove `FEATURE_MOCK_DATA` flag  
- `TODO(analytics)` — Wire telemetry events (`nav_tab_changed`, `flexion_5_reps_direction`, etc.)
