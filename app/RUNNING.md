# Running the CTS patient app

Everything below runs from a self-contained toolchain in `app/.devenv/`
(gitignored). Nothing is installed system-wide.

## One-time setup

The toolchain is already installed on this machine. To recreate it elsewhere:

```bash
# Flutter 3.47.2 (macOS arm64)
mkdir -p app/.devenv && cd app/.devenv
curl -L -o flutter.zip https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.47.2-stable.zip
unzip -q flutter.zip && rm flutter.zip

# Python venv for the backends. MUST be Python 3.9-3.12 — MediaPipe has no
# wheels for 3.13+, and 3.14 breaks its ctypes bindings.
python3.12 -m venv py312
./py312/bin/pip install -r ../PT_accuracy/backend/requirements.txt
```

Then copy `app/supabase.env.example` to `app/supabase.env` and fill in the
project URL and anon key.

## Running

Three processes. Only the first is required — the app runs without either
backend, it just can't measure anything.

### 1. The app

```bash
cd app/PT_accuracy/hand_flexion_app
export PATH="$PWD/../../.devenv/flutter/bin:$PATH"
set -a && . ../../supabase.env && set +a

flutter run -d chrome \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
```

Without the `--dart-define`s the app starts in guest mode: every screen works,
nothing is saved.

### 2. Glove sensor bridge — for the FSR Grip and Pinch tabs

Flutter web cannot open a serial port, so this process owns the USB connection
and rebroadcasts readings over a WebSocket on port 8766.

```bash
cd app/PT_accuracy/backend

# With the glove plugged in (autodetects the port)
../../.devenv/py312/bin/python sensor_ws_server.py

# Without hardware — synthetic data in the firmware's exact format
../../.devenv/py312/bin/python sensor_ws_server.py --simulate

# If autodetect picks the wrong device
../../.devenv/py312/bin/python sensor_ws_server.py --list-ports
../../.devenv/py312/bin/python sensor_ws_server.py --port /dev/cu.usbmodem1101
```

The app shows a clear banner when readings are simulated, so a demo can never
be mistaken for a real measurement.

### 3. Flexion hand-tracking server — for the Flexion tab

Camera-based, needs no glove.

```bash
cd app/PT_accuracy/backend
../../.devenv/py312/bin/python flexion_ws_server.py
```

## Tests

```bash
cd app/PT_accuracy/hand_flexion_app
export PATH="$PWD/../../.devenv/flutter/bin:$PATH"
flutter test test/hold_capture_test.dart   # strength aggregation — 14 tests
```

`flutter test` on its own currently fails to load `test/widget_test.dart`:
it transitively imports `flexion_page.dart`, which uses `dart:html`, and that
library does not exist on the Dart VM where tests run. Pre-existing, unrelated
to the sensor work. Fixing it means moving the browser camera code behind a
conditional import.

## Hardware notes

`firmware/CTS_IC2.ino` prints one line per loop at **115200 baud**:

```
IR=61234 BPM=72 TempC=33.41 FSR=2048
```

- `FSR` is a raw 12-bit ADC value (0–4095), not a calibrated force. The UI
  labels it "raw sensor units" for that reason.
- `IR > 50000` means a finger is on the heart-rate sensor; below that the
  firmware zeroes BPM, so 0 means "unknown", not "no pulse".
- There is **one** FSR channel. The `pinch` table stores two values, so the
  Pinch tab takes index-thumb and middle-thumb as two sequential holds.
- BLE is defined in the firmware but not commissioned; the board is wired
  over USB.

## Known database issue

The dummy CSVs were imported with explicit `id` values without advancing the
tables' identity sequences, so the first insert into a freshly imported table
fails with `duplicate key value violates unique constraint`. The app retries
past it, but the real fix is to run
`app/PT_accuracy/backend/sql/fix_identity_sequences.sql` once in the Supabase
SQL editor.
