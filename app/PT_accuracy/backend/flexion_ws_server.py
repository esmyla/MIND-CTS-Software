import asyncio
import json
import math
import os
import time
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional, Dict, Any

import cv2
import mediapipe as mp
import numpy as np
import websockets

from supabase import create_client, Client

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")

supabase: Optional[Client] = None
if SUPABASE_URL and SUPABASE_KEY:
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# ===================================================================
# CONFIG
# ===================================================================
ANGLE_TOLERANCE = 0.75
RESET_THRESHOLD = 4.0
ANGLE_INCREMENT = 5
NUM_REPS_TO_LEVEL_UP = 5

MAX_ANGLE_TARGET_FORWARD = 70
MIN_ANGLE_TARGET_FORWARD = 25
MAX_ANGLE_TARGET_BACKWARD = 50
MIN_ANGLE_TARGET_BACKWARD = 10

DEFAULT_HANDEDNESS = "Left"   # "Right" or "Left"
DEFAULT_FORWARD_TILT = True   # True forward, False backward

DEFAULT_STATE = {
    "angle_target_forward": 30,
    "angle_target_backward": 15,
    "reps_last_session": 0,
}

# ===================================================================
# SUPABASE HELPERS
# ===================================================================

def get_current_session(user_id: str) -> int:
    if not supabase:
        return 0
    try:
        resp = (
            supabase.table("flexion")
            .select("session")
            .eq("user_id", user_id)
            .order("session", desc=True)
            .limit(1)
            .execute()
        )
        if resp.data:
            return int(resp.data[0]["session"])
        return 0
    except Exception:
        return 0

def load_state(user_id: str) -> Dict[str, Any]:
    if not supabase:
        return {**DEFAULT_STATE, "session": 0}
    try:
        resp = (
            supabase.table("flexion")
            .select("*")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .limit(1)
            .execute()
        )

        if resp.data:
            latest = resp.data[0]
            return {
                "angle_target_forward": float(latest.get("degree_forward", DEFAULT_STATE["angle_target_forward"])),
                "angle_target_backward": float(latest.get("degree_backward", DEFAULT_STATE["angle_target_backward"])),
                "reps_last_session": int(latest.get("repetitions", 0)),
                "session": int(latest.get("session", 0)),
            }
        return {**DEFAULT_STATE, "session": 0}
    except Exception:
        return {**DEFAULT_STATE, "session": 0}

def save_session(
    user_id: str,
    angle_target_forward: int,
    angle_target_backward: int,
    reps_completed: int,
    level_up: bool = False,
) -> None:
    if not supabase:
        print("Supabase not configured; skipping save_session.")
        return
    try:
        session = get_current_session(user_id) + 1
        record = {
            "user_id": user_id,
            "session": session,
            "degree_forward": int(angle_target_forward),
            "degree_backward": int(angle_target_backward),
            "repetitions": int(reps_completed),
            "level_up": bool(level_up),
            "created_at": datetime.utcnow().isoformat(),
        }
        supabase.table("flexion").insert(record).execute()
        print(f"✓ Saved session #{session} (reps={reps_completed}, level_up={level_up})")
    except Exception as e:
        print(f"✗ Error saving session: {e}")

# ===================================================================
# TRACKING STATE
# ===================================================================

@dataclass
class TrackerState:
    user_id: str = "demo-user"
    handedness: str = DEFAULT_HANDEDNESS
    forward_tilt: bool = DEFAULT_FORWARD_TILT

    angle_target_forward: float = 30.0
    angle_target_backward: float = 15.0
    reps_last_session: int = 0

    reps: int = 0
    armed: bool = True
    baseline_id0: Optional[tuple] = None

    last_level_up: bool = False
    last_warning: Optional[str] = None

    last_frame_time: float = field(default_factory=time.time)
    fps: float = 0.0

    def current_target(self) -> float:
        return self.angle_target_forward if self.forward_tilt else self.angle_target_backward

    def direction_str(self) -> str:
        return "forward" if self.forward_tilt else "backward"

# ===================================================================
# MEDIAPIPE TASKS
# ===================================================================

from mediapipe.tasks import python
from mediapipe.tasks.python import vision

MODEL_PATH = os.getenv("HAND_MODEL_PATH", os.path.join("models", "hand_landmarker.task"))

base_options = python.BaseOptions(model_asset_path=MODEL_PATH)
options = vision.HandLandmarkerOptions(
    base_options=base_options,
    num_hands=1,
)
hand_landmarker = vision.HandLandmarker.create_from_options(options)

def compute_angles_from_frame(bgr_img: np.ndarray) -> Dict[str, Any]:
    img = cv2.flip(bgr_img, 1)
    h, w, _ = img.shape
    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
    result = hand_landmarker.detect(mp_image)

    if not result.hand_landmarks:
        return {
            "angle_deg": None,
            "angle_deg_2": None,
            "id0_xy": None,
            "id9_xy": None,
            "id12_xy": None,
            "found_hand": False,
        }

    lm = result.hand_landmarks[0]

    def px(i: int):
        return (int(lm[i].x * w), int(lm[i].y * h))

    id0_xy = px(0)
    id9_xy = px(9)
    id12_xy = px(12)

    dx = id12_xy[0] - id0_xy[0]
    dy = id12_xy[1] - id0_xy[1]
    angle_rad = math.atan2(dx, dy)
    angle_deg = 180 - math.degrees(angle_rad)

    dx2 = id9_xy[0] - id0_xy[0]
    dy2 = id9_xy[1] - id0_xy[1]
    angle_rad_2 = math.atan2(dx2, dy2)
    angle_deg_2 = 180 - math.degrees(angle_rad_2)

    return {
        "angle_deg": angle_deg,
        "angle_deg_2": angle_deg_2,
        "id0_xy": id0_xy,
        "id9_xy": id9_xy,
        "id12_xy": id12_xy,
        "found_hand": True,
    }

# ===================================================================
# REP LOGIC
# ===================================================================

def update_reps_and_warnings(
    state: TrackerState,
    angle_deg: float,
    angle_deg_2: float,
    id0_xy: Optional[tuple],
    id12_xy: Optional[tuple],
) -> None:
    state.last_level_up = False
    state.last_warning = None

    if abs(angle_deg_2 - angle_deg) > 20 and abs(angle_deg_2 - angle_deg) < 300:
        state.last_warning = "Keep your hand straight."

    if id0_xy is not None and id12_xy is not None:
        if state.baseline_id0 is None:
            state.baseline_id0 = id0_xy

        hand_len = math.hypot(id12_xy[0] - id0_xy[0], id12_xy[1] - id0_xy[1])
        if hand_len > 0 and state.baseline_id0 is not None:
            wrist_drift = math.hypot(
                id0_xy[0] - state.baseline_id0[0],
                id0_xy[1] - state.baseline_id0[1],
            )
            if wrist_drift > (hand_len / 3.0):
                state.armed = False
                state.last_warning = "Try not to move your arm, just your wrist."

    current_angle_target = state.current_target()
    handed = state.handedness
    forward = state.forward_tilt
    straight_ok = abs(angle_deg_2 - angle_deg) < 10

    hit_target = (
        (forward and handed == "Right" and angle_deg < (360 - current_angle_target) and angle_deg > 180)
        or ((not forward) and handed == "Right" and angle_deg > current_angle_target and angle_deg < 180)
        or (forward and handed == "Left" and angle_deg > current_angle_target and angle_deg < 180)
        or ((not forward) and handed == "Left" and angle_deg < (360 - current_angle_target) and angle_deg > 180)
    )

    if state.armed and straight_ok and hit_target:
        state.armed = False
        state.reps += 1

        if state.reps >= NUM_REPS_TO_LEVEL_UP:
            save_session(
                state.user_id,
                int(state.angle_target_forward),
                int(state.angle_target_backward),
                state.reps,
                level_up=True,
            )

            state.forward_tilt = not state.forward_tilt
            if state.forward_tilt:
                state.angle_target_forward = min(
                    state.angle_target_forward + ANGLE_INCREMENT, MAX_ANGLE_TARGET_FORWARD
                )
            else:
                state.angle_target_backward = min(
                    state.angle_target_backward + ANGLE_INCREMENT, MAX_ANGLE_TARGET_BACKWARD
                )

            state.reps = 0
            state.last_level_up = True

    if (not state.armed) and (angle_deg <= RESET_THRESHOLD or angle_deg >= (360 - RESET_THRESHOLD)):
        state.armed = True
        if id0_xy is not None:
            state.baseline_id0 = id0_xy

# ===================================================================
# SERVER
# ===================================================================

async def send_update(state: TrackerState, conn, angle: Optional[float]) -> None:
    now = time.time()
    dt = now - state.last_frame_time
    if dt > 0:
        inst = 1.0 / dt
        state.fps = 0.9 * state.fps + 0.1 * inst if state.fps > 0 else inst
    state.last_frame_time = now

    payload = {
        "type": "exercise_update",
        "timestamp": now,
        "angle": float(angle) if angle is not None else 0.0,
        "target_forward": float(state.angle_target_forward),
        "target_backward": float(state.angle_target_backward),
        "reps": int(state.reps),
        "reps_last": int(state.reps_last_session),
        "direction": state.direction_str(),
        "handedness": state.handedness,
        "armed": bool(state.armed),
        "warning": state.last_warning,
        "level_up": bool(state.last_level_up),
        "fps": float(state.fps),
    }
    await conn.send(json.dumps(payload))

async def handler(conn):
    # Newer websockets exposes request metadata under conn.request (incl. path). [2](https://stackoverflow.com/questions/79234060/cannot-access-path-in-websockets-serve-handler)
    raw_path = getattr(getattr(conn, "request", None), "path", "") or ""
    query = raw_path.split("?", 1)

    user_id = "demo-user"
    if len(query) == 2:
        params = query[1]
        for part in params.split("&"):
            if part.startswith("user_id="):
                user_id = part.split("=", 1)[1].strip() or "demo-user"

    state = TrackerState(user_id=user_id)

    loaded = load_state(user_id)
    state.angle_target_forward = float(loaded.get("angle_target_forward", state.angle_target_forward))
    state.angle_target_backward = float(loaded.get("angle_target_backward", state.angle_target_backward))
    state.reps_last_session = int(loaded.get("reps_last_session", 0))

    print(f"[server] client connected user_id={user_id}")

    try:
        async for message in conn:
            if isinstance(message, (bytes, bytearray)):
                jpg = np.frombuffer(message, dtype=np.uint8)
                frame = cv2.imdecode(jpg, cv2.IMREAD_COLOR)
                if frame is None:
                    state.last_warning = "Bad frame received."
                    await send_update(state, conn, angle=None)
                    continue

                info = compute_angles_from_frame(frame)
                angle_deg = info["angle_deg"]
                angle_deg_2 = info["angle_deg_2"]

                if angle_deg is not None and angle_deg_2 is not None:
                    update_reps_and_warnings(
                        state,
                        angle_deg=angle_deg,
                        angle_deg_2=angle_deg_2,
                        id0_xy=info["id0_xy"],
                        id12_xy=info["id12_xy"],
                    )
                    await send_update(state, conn, angle=angle_deg)
                else:
                    state.last_warning = "No hand detected."
                    await send_update(state, conn, angle=None)

            else:
                try:
                    data = json.loads(message)
                except Exception:
                    continue

                cmd = data.get("command")
                if cmd == "toggle_direction":
                    state.forward_tilt = not state.forward_tilt

                elif cmd == "level_up":
                    save_session(
                        state.user_id,
                        int(state.angle_target_forward),
                        int(state.angle_target_backward),
                        state.reps,
                        level_up=False,
                    )
                    if state.forward_tilt:
                        state.angle_target_forward = (
                            state.angle_target_forward + ANGLE_INCREMENT
                            if state.angle_target_forward + ANGLE_INCREMENT <= MAX_ANGLE_TARGET_FORWARD
                            else MIN_ANGLE_TARGET_FORWARD
                        )
                    else:
                        state.angle_target_backward = (
                            state.angle_target_backward + ANGLE_INCREMENT
                            if state.angle_target_backward + ANGLE_INCREMENT <= MAX_ANGLE_TARGET_BACKWARD
                            else MIN_ANGLE_TARGET_BACKWARD
                        )
                    state.reps_last_session = state.reps
                    state.reps = 0
                    state.last_level_up = True

                elif cmd == "set_handedness":
                    handed = data.get("value")
                    if handed in ("Left", "Right"):
                        state.handedness = handed

                elif cmd == "quit":
                    break

                await send_update(state, conn, angle=None)

    finally:
        print(f"[server] client disconnected user_id={user_id}, reps={state.reps}")
        save_session(
            state.user_id,
            int(state.angle_target_forward),
            int(state.angle_target_backward),
            state.reps,
            level_up=False,
        )

async def main():
    host = os.getenv("WS_HOST", "0.0.0.0")
    port = int(os.getenv("WS_PORT", "8765"))
    print(f"Starting server on {host}:{port}")

    # websockets.serve(handler, ...) is the modern entrypoint; avoid legacy protocol types. [1](https://deepwiki.com/python-websockets/websockets/11-migration-guide)
    async with websockets.serve(handler, host, port, max_size=4 * 1024 * 1024):
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())