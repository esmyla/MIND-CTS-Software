"""HTTP bridge between the doctor portal and SAM.

The portal POSTs to /chat with the doctor's Supabase access token in the
Authorization header. That token is forwarded to Postgres, so RLS decides what
the agent can read. No service-role key lives here.
"""

from __future__ import annotations

import json
import os
import sys
import threading
import time
import traceback
from functools import partial
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Dict, List, Tuple

from langchain_core.messages import AIMessage, BaseMessage, HumanMessage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from agent import DoctorSession, open_session, run_agent  # noqa: E402

DEFAULT_PORT = 8700

ALLOWED_ORIGINS = {
    o.strip()
    for o in os.getenv(
        "SAM_ALLOWED_ORIGINS",
        "http://localhost:3100,http://127.0.0.1:3100",
    ).split(",")
    if o.strip()
}

# Verifying a token costs a round trip, so cache briefly. Short TTL bounds how
# long a revoked token keeps working.
_SESSION_TTL_SECONDS = 300
_sessions: Dict[str, Tuple[float, DoctorSession]] = {}
_sessions_lock = threading.Lock()


def _session_for(token: str) -> DoctorSession:
    now = time.time()
    with _sessions_lock:
        cached = _sessions.get(token)
        if cached and now - cached[0] < _SESSION_TTL_SECONDS:
            return cached[1]

    session = open_session(token)

    with _sessions_lock:
        _sessions[token] = (now, session)
        for stale in [k for k, (t, _) in _sessions.items() if now - t > _SESSION_TTL_SECONDS]:
            _sessions.pop(stale, None)
    return session


def _rebuild_history(raw: List[dict]) -> List[BaseMessage]:
    history: List[BaseMessage] = []
    for item in raw[-20:]:
        role = item.get("role")
        content = str(item.get("content", ""))
        if not content:
            continue
        if role == "user":
            history.append(HumanMessage(content=content))
        elif role == "assistant":
            history.append(AIMessage(content=content))
    return history


class SamHandler(BaseHTTPRequestHandler):
    server_version = "SAM/1.0"

    def _cors(self) -> None:
        origin = self.headers.get("Origin", "")
        if origin in ALLOWED_ORIGINS:
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Max-Age", "600")

    def _json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    # Strip the query string: a token must never reach the console.
    def log_message(self, fmt, *args):
        sys.stderr.write(f"[sam] {self.command} {self.path.split('?')[0]}\n")

    def do_OPTIONS(self):  # noqa: N802
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):  # noqa: N802
        if self.path.split("?")[0] == "/health":
            self._json(200, {"ok": True, "service": "sam"})
        else:
            self._json(404, {"error": "Not found"})

    def do_POST(self):  # noqa: N802
        if self.path.split("?")[0] != "/chat":
            self._json(404, {"error": "Not found"})
            return

        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            self._json(401, {"error": "Missing bearer token. Sign in to the portal first."})
            return
        token = auth[len("Bearer "):].strip()

        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            self._json(400, {"error": "Malformed request body."})
            return

        message = str(payload.get("message", "")).strip()
        if not message:
            self._json(400, {"error": "Empty message."})
            return

        try:
            session = _session_for(token)
        except PermissionError as exc:
            self._json(403, {"error": str(exc)})
            return
        except Exception as exc:
            self._json(401, {"error": f"Could not verify your session: {exc}"})
            return

        try:
            history = _rebuild_history(payload.get("history") or [])
            reply = run_agent(session, message, history)
            self._json(200, {"reply": reply.content, "doctor": session.doctor_name})
        except Exception as exc:
            traceback.print_exc()
            self._json(500, {"error": f"SAM failed to answer: {exc}"})


def main() -> None:
    port = int(os.getenv("SAM_PORT", str(DEFAULT_PORT)))
    host = os.getenv("SAM_HOST", "127.0.0.1")
    print(f"[sam] listening on http://{host}:{port}")
    print(f"[sam] allowed origins: {', '.join(sorted(ALLOWED_ORIGINS))}")
    ThreadingHTTPServer((host, port), partial(SamHandler)).serve_forever()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n[sam] stopped")
