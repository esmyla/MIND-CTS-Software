import asyncio
import json
import math
import os
import time
import traceback
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional, Dict, Any, Tuple

import cv2
import mediapipe as mp
import numpy as np
import websockets

from supabase import create_client, Client

# =============================================================================
# SUPABASE CONFIG
# =============================================================================
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")

supabase: Optional[Client] = None
if SUPABASE_URL and SUPABASE_KEY:
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# =============================================================================
# CONFIG
# =============================================================================
RESET_THRESHOLD = 4.0
ANGLE_INCREMENT = 5
NUM_REPS_TO_LEVEL_UP = 5

MAX_ANGLE_TARGET_FORWARD = 70
MIN_ANGLE_TARGET_FORWARD = 25
MAX_ANGLE_TARGET_BACKWARD = 50
MIN_ANGLE_TARGET_BACKWARD = 10

DEFAULT_HANDEDNESS = "Left"     # "Left" or "Right"
DEFAULT_FORWARD_TILT = True     # True forward, False backward

DEFAULT_STATE = {
    "angle_target_forward": 30,
    "angle_target_backward": 15,
    "reps_last_session": 0,
}

# =============================================================================
# SUPABASE HELPERS
# =============================================================================
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


# =============================================================================
# ANGLE + SIGN HELPERS
# =============================================================================
def normalize_180(angle_0_360: float) -> float:
    """Convert angle from 0..360 into -180..180."""
    return angle_0_360 if angle_0_360 <= 180 else angle_0_360 - 360


def expected_sign(handedness: str, forward_tilt: bool) -> int:
    """
    Corrected sign rules:

    Left  + forward  => +1  (angle should be positive)
    Left  + backward => -1  (angle should be negative)
    Right + forward  => -1  (angle should be negative)
    Right + backward => +1  (angle should be positive)
    """
    if handedness == "Left":
        return 1 if forward_tilt else -1
    else:  # Right
        return -1 if forward_tilt else 1


# =============================================================================
# TRACKER STATE
# =============================================================================
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
    baseline_id0: Optional[Tuple[int, int]] = None

    last_level_up: bool = False
    last_warning: Optional[str] = None

    # UI always gets the true signed angle (-180..180)
    last_angle_signed: float = 0.0
    last_found_hand: bool = False

    # Optional debug (effective = sign * signed)
    last_angle_effective: float = 0.0

    # Monotonic timestamp for MediaPipe VIDEO mode (strictly increasing!)
    video_ts_ms: int = 0

    # FPS estimation
    last_frame_time: float = field(default_factory=time.time)
    fps: float = 0.0

    def direction_str(self) -> str:
        return "forward" if self.forward_tilt else "backward"


# =============================================================================
# MEDIAPIPE TASKS (VIDEO MODE)
# =============================================================================
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

MODEL_PATH = os.getenv("HAND_MODEL_PATH", os.path.join("models", "hand_landmarker.task"))


def make_hand_landmarker() -> "vision.HandLandmarker":
    """Create a HandLandmarker configured for streaming video (stable)."""
    base_options = python.BaseOptions(model_asset_path=MODEL_PATH)
    options = vision.HandLandmarkerOptions(
        base_options=base_options,
        running_mode=vision.RunningMode.VIDEO,
        num_hands=1,
        min_hand_detection_confidence=0.4,
        min_hand_presence_confidence=0.4,
        min_tracking_confidence=0.25,
    )
    return vision.HandLandmarker.create_from_options(options)


def compute_angles_from_frame(
    bgr_img: np.ndarray,
    landmarker: "vision.HandLandmarker",
    timestamp_ms: int
) -> Dict[str, Any]:
    """
    Returns raw angles in 0..360 plus key pixel points for drift logic.
    Uses VIDEO mode: detect_for_video(mp_image, timestamp_ms).
    """
    img = cv2.flip(bgr_img, 1)  # mirror like your original UX
    h, w, _ = img.shape
    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
    result = landmarker.detect_for_video(mp_image, timestamp_ms)

    if not result.hand_landmarks:
        return {"found_hand": False}

    lm = result.hand_landmarks[0]

    def px(i: int):
        return (int(lm[i].x * w), int(lm[i].y * h))

    id0_xy = px(0)   # wrist
    id9_xy = px(9)   # middle MCP
    id12_xy = px(12) # middle tip

    dx = id12_xy[0] - id0_xy[0]
    dy = id12_xy[1] - id0_xy[1]
    angle_deg = 180 - math.degrees(math.atan2(dx, dy))  # 0..360

    dx2 = id9_xy[0] - id0_xy[0]
    dy2 = id9_xy[1] - id0_xy[1]
    angle_deg_2 = 180 - math.degrees(math.atan2(dx2, dy2))  # 0..360

    return {
        "found_hand": True,
        "angle_deg": float(angle_deg),
        "angle_deg_2": float(angle_deg_2),
        "id0_xy": id0_xy,
        "id12_xy": id12_xy,
    }


# =============================================================================
# REP LOGIC (SIGNED UI ANGLE + EFFECTIVE REP ANGLE)
# =============================================================================
def update_reps_and_warnings(
    state: TrackerState,
    signed_angle: float,
    signed_angle_2: float,
    effective_angle: float,
    effective_angle_2: float,
    id0_xy: Optional[Tuple[int, int]],
    id12_xy: Optional[Tuple[int, int]],
) -> None:
    state.last_level_up = False
    state.last_warning = None

    # Alignment warning (use signed domain for consistency)
    if abs(signed_angle_2 - signed_angle) > 20:
        state.last_warning = "Keep your hand straight."

    # Drift detection
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

    # Straightness check should match rep domain (effective)
    straight_ok = abs(effective_angle_2 - effective_angle) < 10

    # Target magnitude: forward uses forward target, backward uses backward target
    target = state.angle_target_forward if state.forward_tilt else state.angle_target_backward

    # Rep trigger: effective must exceed target. Wrong sign => effective negative => won't pass.
    hit_target = effective_angle >= target

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

            # Toggle direction and level up for next direction
            state.forward_tilt = not state.forward_tilt

            if state.forward_tilt:
                state.angle_target_forward = min(state.angle_target_forward + ANGLE_INCREMENT, MAX_ANGLE_TARGET_FORWARD)
            else:
                state.angle_target_backward = min(state.angle_target_backward + ANGLE_INCREMENT, MAX_ANGLE_TARGET_BACKWARD)

            state.reps = 0
            state.last_level_up = True

    # Rearm near neutral based on signed angle around 0
    if (not state.armed) and (abs(signed_angle) <= RESET_THRESHOLD):
        state.armed = True
        if id0_xy is not None:
            state.baseline_id0 = id0_xy


# =============================================================================
# SERVER OUTPUT
# =============================================================================
async def send_update(state: TrackerState, conn) -> None:
    now = time.time()
    dt = now - state.last_frame_time
    if dt > 0:
        inst = 1.0 / dt
        state.fps = 0.9 * state.fps + 0.1 * inst if state.fps > 0 else inst
    state.last_frame_time = now

    payload = {
        "type": "exercise_update",
        "timestamp": now,

        # ✅ True signed angle (UI: -180..180 always)
        "angle": float(state.last_angle_signed),
        "found_hand": bool(state.last_found_hand),

        # Targets remain magnitudes (UI can sign them if desired)
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

        # optional debug visibility
        "expected_sign": expected_sign(state.handedness, state.forward_tilt),
        "effective_angle": float(state.last_angle_effective),
    }
    await conn.send(json.dumps(payload))


# =============================================================================
# CONNECTION HANDLER
# =============================================================================
async def handler(conn):
    raw_path = getattr(getattr(conn, "request", None), "path", "") or ""
    query = raw_path.split("?", 1)

    user_id = "demo-user"
    if len(query) == 2:
        params = query[1]
        for part in params.split("&"):  # ✅ correct separator
            if part.startswith("user_id="):
                user_id = part.split("=", 1)[1].strip() or "demo-user"

    state = TrackerState(user_id=user_id)

    loaded = load_state(user_id)
    state.angle_target_forward = float(loaded.get("angle_target_forward", state.angle_target_forward))
    state.angle_target_backward = float(loaded.get("angle_target_backward", state.angle_target_backward))
    state.reps_last_session = int(loaded.get("reps_last_session", 0))

    print(f"[server] client connected user_id={user_id}")

    landmarker = make_hand_landmarker()

    try:
        async for message in conn:
            # -----------------------
            # Binary JPEG frames
            # -----------------------
            if isinstance(message, (bytes, bytearray)):
                jpg = np.frombuffer(message, dtype=np.uint8)
                frame = cv2.imdecode(jpg, cv2.IMREAD_COLOR)

                if frame is None:
                    state.last_found_hand = False
                    state.last_warning = "Bad frame received."
                    await send_update(state, conn)
                    continue

                # ✅ Strictly increasing timestamp required by detect_for_video
                ts_now = int(time.time() * 1000)
                ts_ms = ts_now if ts_now > state.video_ts_ms else state.video_ts_ms + 1
                state.video_ts_ms = ts_ms

                info = compute_angles_from_frame(frame, landmarker, ts_ms)

                if not info.get("found_hand", False):
                    state.last_found_hand = False
                    state.last_warning = "No hand detected."
                    await send_update(state, conn)
                    continue

                raw_a1 = float(info["angle_deg"])
                raw_a2 = float(info["angle_deg_2"])

                signed_a1 = normalize_180(raw_a1)
                signed_a2 = normalize_180(raw_a2)

                sign = expected_sign(state.handedness, state.forward_tilt)
                effective_a1 = sign * signed_a1
                effective_a2 = sign * signed_a2

                # store last values
                state.last_angle_signed = signed_a1
                state.last_angle_effective = effective_a1
                state.last_found_hand = True

                update_reps_and_warnings(
                    state=state,
                    signed_angle=signed_a1,
                    signed_angle_2=signed_a2,
                    effective_angle=effective_a1,
                    effective_angle_2=effective_a2,
                    id0_xy=info.get("id0_xy"),
                    id12_xy=info.get("id12_xy"),
                )

                await send_update(state, conn)

            # -----------------------
            # JSON text commands
            # -----------------------
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

                # Always send back full state + last angle
                await send_update(state, conn)

    except Exception as e:
        print("[server] handler exception:", repr(e))
        traceback.print_exc()

    finally:
        print(f"[server] client disconnected user_id={user_id}, reps={state.reps}")
        save_session(
            state.user_id,
            int(state.angle_target_forward),
            int(state.angle_target_backward),
            state.reps,
            level_up=False,
        )
        try:
            landmarker.close()
        except Exception:
            pass


# =============================================================================
# MAIN
# =============================================================================
async def main():
    host = os.getenv("WS_HOST", "0.0.0.0")
    port = int(os.getenv("WS_PORT", "8765"))
    print(f"Starting server on {host}:{port}")

    async with websockets.serve(
        handler,
        host,
        port,
        max_size=4 * 1024 * 1024,
        ping_interval=20,
        ping_timeout=20,
    ):
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())