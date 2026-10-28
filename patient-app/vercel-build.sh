#!/usr/bin/env bash
#
# Vercel build for the Flutter web app.
#
# Vercel's build image has no Flutter, so we fetch a pinned SDK release. Pinned
# rather than "stable" on purpose: a silent SDK bump should not be able to break
# a deploy nobody touched.
#
# Required Vercel environment variables (Project -> Settings -> Environment
# Variables). Both are public-by-design client values, not secrets:
#   SUPABASE_URL
#   SUPABASE_ANON_KEY
#
# Optional, only if the Python backends are reachable from the public internet:
#   WS_URL          wss://... for the flexion hand-tracking server
#   SENSOR_WS_URL   wss://... for the glove sensor bridge
# Leave them unset for a normal deploy. They MUST be wss:// (not ws://) — a page
# served over HTTPS cannot open an insecure WebSocket, the browser blocks it.

set -euo pipefail

FLUTTER_VERSION="3.47.2"
FLUTTER_DIR="/tmp/flutter"
ARCHIVE="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
BASE_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux"

echo "==> Fetching Flutter ${FLUTTER_VERSION}"
curl -fsSL "${BASE_URL}/${ARCHIVE}" -o "/tmp/${ARCHIVE}"
tar -xJf "/tmp/${ARCHIVE}" -C /tmp
export PATH="${FLUTTER_DIR}/bin:${PATH}"

# Flutter shells out to git for its version; the build user does not own the
# extracted tree, so git refuses to read it without this.
git config --global --add safe.directory "${FLUTTER_DIR}" || true

echo "==> Flutter $(flutter --version | head -n 1)"
flutter config --no-analytics >/dev/null 2>&1 || true
flutter pub get

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  echo "!!  SUPABASE_URL / SUPABASE_ANON_KEY are not set."
  echo "!!  Building anyway — the app will start in guest mode and save nothing."
fi

echo "==> Building web bundle"
flutter build web --release \
  --no-wasm-dry-run \
  --dart-define=SUPABASE_URL="${SUPABASE_URL:-}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}" \
  --dart-define=WS_URL="${WS_URL:-}" \
  --dart-define=SENSOR_WS_URL="${SENSOR_WS_URL:-}"

echo "==> Built build/web"
