"""
Main Wrist Flexion Exercise (Flutter Controlled)
================================================

Tracks wrist flexion reps and streams real-time data to Flutter.

Features
--------
• MediaPipe wrist angle tracking
• WebSocket real-time streaming
• Flutter commands (start/pause/stop)
• Rep counting
• Supabase session storage
"""

import cv2
import mediapipe as mp
import asyncio
import websockets
import threading
import json
import math
import time
import os
from datetime import datetime
from supabase import create_client

# ==========================================================
# CONFIG
# ==========================================================

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

TARGET_FORWARD = 30
TARGET_BACKWARD = 15
RESET_THRESHOLD = 4

HANDEDNESS = "Left"

# ==========================================================
# GLOBAL STATE (STREAMED TO FLUTTER)
# ==========================================================

exercise_state = {
    "phase": "idle",           # idle / running / paused / finished
    "angle": 0.0,
    "direction": "forward",
    "target_forward": TARGET_FORWARD,
    "target_backward": TARGET_BACKWARD,
    "reps": 0,
    "armed": True,
    "warning": None,
    "session_time": 0,
    "message": "Press start in the app"
}

command_queue = []
quit_requested = False


# ==========================================================
# WEBSOCKET SERVER
# ==========================================================

async def handle_websocket(websocket, path):

    global command_queue

    print("✓ Flutter connected")

    try:
        while not quit_requested:

            await websocket.send(json.dumps(exercise_state))

            try:
                msg = await asyncio.wait_for(websocket.recv(), timeout=0.01)

                data = json.loads(msg)

                if "command" in data:
                    command_queue.append(data["command"])

            except asyncio.TimeoutError:
                pass

            await asyncio.sleep(0.033)

    except websockets.exceptions.ConnectionClosed:
        print("Flutter disconnected")


async def start_server():

    server = await websockets.serve(handle_websocket, "localhost", 8765)

    print("✓ WebSocket server running")

    await server.wait_closed()


# ==========================================================
# ANGLE CALCULATION
# ==========================================================

def calculate_angle(p1, p2):

    dx = p2[0] - p1[0]
    dy = p2[1] - p1[1]

    angle = 180 - math.degrees(math.atan2(dx, dy))

    return angle


# ==========================================================
# SAVE SESSION
# ==========================================================

def save_session(user_id, reps):

    supabase.table("flexion").insert({

        "user_id": user_id,
        "repetitions": reps,
        "created_at": datetime.utcnow().isoformat()

    }).execute()


# ==========================================================
# MAIN LOOP
# ==========================================================

def run_exercise():

    global exercise_state

    USER_ID = "demo-user"

    cap = cv2.VideoCapture(0)

    mpHands = mp.solutions.hands

    hands = mpHands.Hands(
        static_image_mode=False,
        max_num_hands=1
    )

    mpDraw = mp.solutions.drawing_utils

    reps = 0
    armed = True
    forward = True

    start_time = None

    while True:

        # ----------------------------------
        # HANDLE COMMANDS FROM FLUTTER
        # ----------------------------------

        while command_queue:

            cmd = command_queue.pop(0)

            if cmd == "start":

                exercise_state["phase"] = "running"
                start_time = time.time()

            elif cmd == "pause":

                exercise_state["phase"] = "paused"

            elif cmd == "stop":

                exercise_state["phase"] = "finished"
                save_session(USER_ID, reps)
                return

            elif cmd == "toggle_direction":

                forward = not forward

        # ----------------------------------
        # CAMERA FRAME
        # ----------------------------------

        success, img = cap.read()

        if not success:
            continue

        img = cv2.flip(img, 1)

        imgRGB = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

        results = hands.process(imgRGB)

        id0 = None
        id12 = None

        if results.multi_hand_landmarks:

            for handLms in results.multi_hand_landmarks:

                mpDraw.draw_landmarks(
                    img,
                    handLms,
                    mpHands.HAND_CONNECTIONS
                )

                for i, lm in enumerate(handLms.landmark):

                    h, w, _ = img.shape

                    cx, cy = int(lm.x*w), int(lm.y*h)

                    if i == 0:
                        id0 = (cx,cy)

                    if i == 12:
                        id12 = (cx,cy)

        angle = None

        if id0 and id12:

            angle = calculate_angle(id0,id12)

        # ----------------------------------
        # REP DETECTION
        # ----------------------------------

        if angle:

            target = TARGET_FORWARD if forward else TARGET_BACKWARD

            if armed and angle > target:

                reps += 1
                armed = False

            if not armed and angle < RESET_THRESHOLD:

                armed = True

        # ----------------------------------
        # UPDATE STATE
        # ----------------------------------

        if start_time:

            exercise_state["session_time"] = time.time() - start_time

        exercise_state.update({

            "angle": angle if angle else 0,
            "reps": reps,
            "direction": "forward" if forward else "backward",
            "armed": armed

        })

        cv2.imshow("Wrist Trainer", img)

        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

    cap.release()
    cv2.destroyAllWindows()


# ==========================================================
# MAIN
# ==========================================================

def main():

    def run_ws():

        asyncio.set_event_loop(asyncio.new_event_loop())

        asyncio.get_event_loop().run_until_complete(start_server())

    threading.Thread(target=run_ws, daemon=True).start()

    time.sleep(0.5)

    run_exercise()


if __name__ == "__main__":
    main()