"""
Wrist Flexion Tracking Application with Supabase Integration and WebSocket Support
===================================================================================
This application tracks wrist flexion angles using MediaPipe hand tracking,
stores progress data in Supabase, and streams real-time data to Flutter app.

Dependencies:
- OpenCV (cv2): Video capture and image processing
- MediaPipe: Hand landmark detection
- Supabase: Cloud database for persistent storage
- websockets: Real-time communication with Flutter app
- asyncio: Async WebSocket server
"""

import cv2
import mediapipe as mp
import time
import sys
import math
import json
import os
from supabase import create_client, Client
from typing import Optional
from datetime import datetime

# WebSocket imports
import asyncio
import websockets
import threading

# ===================================================================
# VISUAL AND LOGIC CONFIGURATION
# ===================================================================
ANGLE_TOLERANCE = 0.75
RESET_THRESHOLD = 4.0

LINE_COLOR = (0, 255, 0)
VERT_COLOR = (0, 255, 255)
TEXT_COLOR = (255, 0, 255)
HUD_COLOR = (255, 255, 255)

# ===================================================================
# SUPABASE CONFIGURATION
# ===================================================================
SUPABASE_URL = os.getenv("SUPABASE_URL", "https://cmmumwwzydfebahhgfyi.supabase.co")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNtbXVtd3d6eWRmZWJhaGhnZnlpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI4MDkwNTAsImV4cCI6MjA3ODM4NTA1MH0.zJBi0owKoaycNzmtAm9_5ZsUwXIUmxAGuCy0AhsaoZc")
supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# ===================================================================
# PROGRESSION SYSTEM CONSTANTS
# ===================================================================
DEFAULT_STATE = {
    "angle_target_forward": 30,
    "angle_target_backward": 15,
    "reps_last_session": 0,
}

MAX_ANGLE_TARGET_FORWARD = 70
MIN_ANGLE_TARGET_FORWARD = 25
MAX_ANGLE_TARGET_BACKWARD = 50
MIN_ANGLE_TARGET_BACKWARD = 10

ANGLE_INCREMENT = 5
NUM_REPS_TO_LEVEL_UP = 5

HANDEDNESS = "Left"
FORWARD_TILT = True

# ===================================================================
# GLOBAL STATE FOR WEBSOCKET
# ===================================================================
current_state = {
    "angle": 0.0,
    "target_forward": 30.0,
    "target_backward": 15.0,
    "reps": 0,
    "reps_last": 0,
    "direction": "forward",
    "armed": True,
    "warning": None,
    "level_up": False
}

# Global variables for command handling
command_queue = []
quit_requested = False

# ===================================================================
# AUDIO FEEDBACK FUNCTION
# ===================================================================
def ding():
    print("\a", end="", flush=True)

# ===================================================================
# DATABASE QUERY FUNCTIONS
# ===================================================================
def get_current_session(user_id: str) -> int:
    try:
        response = supabase.table("flexion")\
            .select("session")\
            .eq("user_id", user_id)\
            .order("session", desc=True)\
            .limit(1)\
            .execute()
        
        if response.data:
            return response.data[0]["session"]
        return 0
    except Exception as e:
        print(f"Error getting current session: {e}")
        return 0

def get_last_session_reps(user_id: str) -> int:
    try:
        response = supabase.table("flexion")\
            .select("repetitions")\
            .eq("user_id", user_id)\
            .order("session", desc=True)\
            .limit(1)\
            .execute()
        
        if response.data:
            return response.data[0]["repetitions"]
        return 0
    except Exception as e:
        print(f"Error getting last session reps: {e}")
        return 0

def load_state(user_id: str) -> dict:
    try:
        response = supabase.table("flexion")\
            .select("*")\
            .eq("user_id", user_id)\
            .order("created_at", desc=True)\
            .limit(1)\
            .execute()
        
        if response.data:
            latest = response.data[0]
            return {
                "angle_target_forward": latest.get("degree_forward", DEFAULT_STATE["angle_target_forward"]),
                "angle_target_backward": latest.get("degree_backward", DEFAULT_STATE["angle_target_backward"]),
                "reps_last_session": latest["repetitions"],
                "session": latest["session"],
            }
        
        return {**DEFAULT_STATE, "session": 0}
    except Exception as e:
        print(f"Error loading state from Supabase: {e}")
        return {**DEFAULT_STATE, "session": 0}

def save_session(user_id: str, angle_target_forward: int, angle_target_backward: int, 
                reps_completed: int, level_up: bool = False) -> None:
    try:
        current_session = get_current_session(user_id)
        current_session += 1
        
        record = {
            "user_id": user_id,
            "session": current_session,
            "degree_forward": angle_target_forward,
            "degree_backward": angle_target_backward,
            "repetitions": reps_completed,
            "level_up": level_up,
            "created_at": datetime.utcnow().isoformat()
        }
        
        response = supabase.table("flexion").insert(record).execute()
        
        if response.data:
            print(f"✓ Session saved: {reps_completed} reps at {angle_target_forward}°F/{angle_target_backward}°B (Session #{current_session})")
        
    except Exception as e:
        print(f"✗ Error saving session to Supabase: {e}")

# ===================================================================
# WEBSOCKET SERVER FUNCTIONS
# ===================================================================
async def handle_websocket(websocket, path):
    """
    Handle WebSocket connection from Flutter app.
    Sends real-time exercise data and receives commands.
    """
    print(f"✓ Flutter app connected from {websocket.remote_address}")
    
    global command_queue
    
    try:
        while not quit_requested:
            # Send current state to Flutter app
            try:
                await websocket.send(json.dumps(current_state))
            except Exception as e:
                print(f"Error sending to Flutter: {e}")
                break
            
            # Check for commands from Flutter
            try:
                message = await asyncio.wait_for(websocket.recv(), timeout=0.01)
                command_data = json.loads(message)
                command = command_data.get("command")
                
                if command:
                    command_queue.append(command)
                    print(f"→ Command received from Flutter: {command}")
                    
            except asyncio.TimeoutError:
                pass  # No command received
            except websockets.exceptions.ConnectionClosed:
                break
            except Exception as e:
                print(f"Error receiving from Flutter: {e}")
                break
            
            # Send updates ~30 times per second
            await asyncio.sleep(0.033)
            
    except websockets.exceptions.ConnectionClosed:
        print("✗ Flutter app disconnected")
    except Exception as e:
        print(f"✗ WebSocket error: {e}")

async def start_websocket_server():
    """Start WebSocket server on localhost:8765"""
    try:
        server = await websockets.serve(handle_websocket, "localhost", 8765)
        print("✓ WebSocket server started on ws://localhost:8765")
        print("  Waiting for Flutter app to connect...")
        await server.wait_closed()
    except Exception as e:
        print(f"✗ Failed to start WebSocket server: {e}")
        print("  Make sure port 8765 is not in use by another program")

# ===================================================================
# MAIN APPLICATION
# ===================================================================
def main():
    global current_state, FORWARD_TILT, angle_target_forward, angle_target_backward, command_queue, quit_requested
    
    # Start WebSocket server in background thread
    def run_websocket():
        asyncio.set_event_loop(asyncio.new_event_loop())
        asyncio.get_event_loop().run_until_complete(start_websocket_server())
    
    websocket_thread = threading.Thread(target=run_websocket, daemon=True)
    websocket_thread.start()
    print("✓ WebSocket thread started")
    
    # Give WebSocket server time to start
    time.sleep(0.5)
    
    USER_ID = "stephen-uuid-1234-5678-9012-abcdefabcdef"
    
    state = load_state(USER_ID)
    angle_target_forward = float(state.get("angle_target_forward", DEFAULT_STATE["angle_target_forward"]))
    angle_target_backward = float(state.get("angle_target_backward", DEFAULT_STATE["angle_target_backward"]))
    reps_last_session = int(state.get("reps_last_session", DEFAULT_STATE["reps_last_session"]))

    current_angle_target = angle_target_forward if FORWARD_TILT else angle_target_backward

    # Update global state
    current_state.update({
        "target_forward": angle_target_forward,
        "target_backward": angle_target_backward,
        "reps_last": reps_last_session,
        "direction": "forward" if FORWARD_TILT else "backward",
    })

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("Error: Could not open webcam.")
        sys.exit(1)

    mpHands = mp.solutions.hands
    hands = mpHands.Hands(
        static_image_mode=False,
        max_num_hands=1,
        min_detection_confidence=0.4,
        min_tracking_confidence=0.25
    )
    mpDraw = mp.solutions.drawing_utils

    landmark_spec = mpDraw.DrawingSpec(color=(80, 220, 100), thickness=1, circle_radius=1)
    connection_spec = mpDraw.DrawingSpec(color=(0, 180, 255), thickness=1, circle_radius=1)

    pTime = 0
    fingertip_ids = {4, 8, 12, 16, 20}
    
    armed = True
    reps = 0
    baseline_id0 = None

    show_message = False
    message_start = 0
    message_duration = 2.0

    try:
        while True:
            # Process commands from Flutter app
            while command_queue:
                command = command_queue.pop(0)
                
                if command == "toggle_direction":
                    save_session(USER_ID, int(angle_target_forward), int(angle_target_backward), reps, level_up=False)
                    FORWARD_TILT = not FORWARD_TILT
                    current_state["direction"] = "forward" if FORWARD_TILT else "backward"
                    reps_last_session = reps
                    reps = 0
                    print(f"→ Direction toggled to: {'Forward' if FORWARD_TILT else 'Backward'}")
                    
                elif command == "level_up":
                    save_session(USER_ID, int(angle_target_forward), int(angle_target_backward), reps, level_up=False)
                    
                    if FORWARD_TILT:
                        if angle_target_forward + ANGLE_INCREMENT <= MAX_ANGLE_TARGET_FORWARD:
                            angle_target_forward += ANGLE_INCREMENT
                        else:
                            angle_target_forward = MIN_ANGLE_TARGET_FORWARD
                    else:
                        if angle_target_backward + ANGLE_INCREMENT <= MAX_ANGLE_TARGET_BACKWARD:
                            angle_target_backward += ANGLE_INCREMENT
                        else:
                            angle_target_backward = MIN_ANGLE_TARGET_BACKWARD
                    
                    reps_last_session = reps
                    reps = 0
                    print(f"→ Manual level up: Forward={angle_target_forward}°, Backward={angle_target_backward}°")
                    
                elif command == "quit":
                    print("→ Quit command received from Flutter app")
                    quit_requested = True
                    break
            
            if quit_requested:
                break
            
            current_angle_target = angle_target_forward if FORWARD_TILT else angle_target_backward
            
            success, img = cap.read()
            if not success:
                continue

            img = cv2.flip(img, 1)
            imgRGB = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            results = hands.process(imgRGB)

            h, w, _ = img.shape

            vertical_x = w // 2
            overlay = img.copy()
            cv2.line(overlay, (vertical_x, 0), (vertical_x, h - 1), VERT_COLOR, 2)
            cv2.addWeighted(overlay, 0.1, img, 0.7, 0, img)

            id0_xy = None
            id12_xy = None
            id9_xy = None
            angle_deg = None
            angle_deg_2 = None
            warn_text = None

            if results.multi_hand_landmarks:
                for handLms in results.multi_hand_landmarks:
                    mpDraw.draw_landmarks(
                        img,
                        handLms,
                        mpHands.HAND_CONNECTIONS,
                        landmark_drawing_spec=landmark_spec,
                        connection_drawing_spec=connection_spec
                    )

                    for idx, lm in enumerate(handLms.landmark):
                        cx, cy = int(lm.x * w), int(lm.y * h)

                        if idx in fingertip_ids:
                            cv2.circle(img, (cx, cy), 2, (255, 0, 255), cv2.FILLED)

                        if idx == 0:
                            id0_xy = (cx, cy)
                        elif idx == 9:
                            id9_xy = (cx, cy)
                        elif idx == 12:
                            id12_xy = (cx, cy)

                    if id0_xy is not None and id12_xy is not None:
                        cv2.line(img, id0_xy, id12_xy, LINE_COLOR, 1)
                        cv2.circle(img, id0_xy, 1, LINE_COLOR, cv2.FILLED)
                        cv2.circle(img, id12_xy, 1, LINE_COLOR, cv2.FILLED)

                        dx = id12_xy[0] - id0_xy[0]
                        dy = id12_xy[1] - id0_xy[1]

                        angle_rad = math.atan2(dx, dy)
                        angle_deg = 180 - math.degrees(angle_rad)

                    if id0_xy is not None and id9_xy is not None:
                        cv2.line(img, id0_xy, id9_xy, LINE_COLOR, 1)
                        cv2.circle(img, id0_xy, 1, LINE_COLOR, cv2.FILLED)
                        cv2.circle(img, id9_xy, 1, LINE_COLOR, cv2.FILLED)

                        dx2 = id9_xy[0] - id0_xy[0]
                        dy2 = id9_xy[1] - id0_xy[1]

                        angle_rad_2 = math.atan2(dx2, dy2)
                        angle_deg_2 = 180 - math.degrees(angle_rad_2)

            if angle_deg is not None:
                cv2.putText(
                    img, f"Angle: {angle_deg:4.1f} deg",
                    (10, 120), cv2.FONT_HERSHEY_PLAIN, 2, TEXT_COLOR, 2
                )
            else:
                cv2.putText(
                    img, "Angle: --.-",
                    (10, 120), cv2.FONT_HERSHEY_PLAIN, 2, TEXT_COLOR, 2
                )

            if angle_deg is not None and angle_deg_2 is not None:
                
                if armed and (abs(angle_deg_2 - angle_deg) < 10) and (
                    (FORWARD_TILT and HANDEDNESS == "Right" and angle_deg < (360 - current_angle_target) and angle_deg > 180) or
                    (not FORWARD_TILT and HANDEDNESS == "Right" and angle_deg > current_angle_target and angle_deg < 180) or
                    (FORWARD_TILT and HANDEDNESS == "Left" and angle_deg > current_angle_target and angle_deg < 180) or
                    (not FORWARD_TILT and HANDEDNESS == "Left" and angle_deg < (360-current_angle_target) and angle_deg > 180)):
                    ding()
                    armed = False
                    reps += 1

                    if reps >= NUM_REPS_TO_LEVEL_UP:
                        show_message = True
                        message_start = time.time()
                        FORWARD_TILT = False if FORWARD_TILT else True
                        direction = "Forward" if FORWARD_TILT else "Backward"
                        new_target = angle_target_forward if FORWARD_TILT else angle_target_backward

                        save_session(USER_ID, int(angle_target_forward), int(angle_target_backward), reps, level_up=True)

                        current_state["level_up"] = True

                        if FORWARD_TILT:
                            angle_target_forward += ANGLE_INCREMENT
                        else:
                            angle_target_backward += ANGLE_INCREMENT

                        reps = 0

                    cv2.putText(img, "DING!", (w // 2 - 70, 120),
                                cv2.FONT_HERSHEY_PLAIN, 3, (0, 200, 255), 3)

                if (abs(angle_deg_2 - angle_deg) > 20 and abs(angle_deg_2 - angle_deg) < 300):
                    warn_text = "Keep your hand straight."
                    x_text = max(10, w // 2 - 150)
                    cv2.putText(img, warn_text, (x_text, 80),
                                cv2.FONT_HERSHEY_PLAIN, 1.5, (0, 0, 255), 2)

                if (not armed) and (angle_deg <= RESET_THRESHOLD or angle_deg >= (360 - RESET_THRESHOLD)):
                    armed = True
                    if id0_xy is not None:
                        baseline_id0 = id0_xy

                if (id0_xy is not None and id12_xy is not None):
                    if baseline_id0 is None:
                        baseline_id0 = id0_xy

                    hand_len = math.hypot(id12_xy[0] - id0_xy[0], id12_xy[1] - id0_xy[1])

                    if hand_len > 0:
                        wrist_drift = math.hypot(id0_xy[0] - baseline_id0[0], 
                                                 id0_xy[1] - baseline_id0[1])
                        
                        if wrist_drift > (hand_len / 3.0):
                            armed = False
                            warn_text = "Try not to move your arm, just your wrist."
                            x_text = max(10, w // 2 - 320)
                            cv2.putText(img, warn_text, (x_text, 50),
                                        cv2.FONT_HERSHEY_PLAIN, 1.5, (0, 0, 255), 2)

            # Update WebSocket state
            current_state.update({
                "angle": angle_deg if angle_deg is not None else 0.0,
                "target_forward": angle_target_forward,
                "target_backward": angle_target_backward,
                "reps": reps,
                "reps_last": reps_last_session,
                "direction": "forward" if FORWARD_TILT else "backward",
                "armed": armed,
                "warning": warn_text,
                "level_up": show_message
            })

            # HUD Display
            tilt = "Forward" if FORWARD_TILT else "Backward"
            cv2.putText(img, f"Target ({tilt}): {int(current_angle_target)} deg  [F:{int(angle_target_forward)}° B:{int(angle_target_backward)}°]", 
                       (10, 160), cv2.FONT_HERSHEY_PLAIN, 1.7, HUD_COLOR, 2)
            
            if reps_last_session > 0:
                cv2.putText(img, f"Reps: {reps} (Last: {reps_last_session})", (10, 200),
                            cv2.FONT_HERSHEY_PLAIN, 2, HUD_COLOR, 2)
            else:
                cv2.putText(img, f"Reps: {reps}", (10, 200),
                            cv2.FONT_HERSHEY_PLAIN, 2, HUD_COLOR, 2)

            cv2.putText(img, "'q' quit | 'l' level up | 'b' toggle direction     Hand: " + HANDEDNESS, 
                       (10, h - 20), cv2.FONT_HERSHEY_PLAIN, 1, HUD_COLOR, 1)

            frame_to_show = img.copy()

            if show_message:
                if time.time() - message_start < message_duration:
                    direction = "Forward" if FORWARD_TILT else "Backward"
                    new_target = angle_target_forward if FORWARD_TILT else angle_target_backward
                    cv2.putText(
                        frame_to_show,
                        f"Level Up! New {direction} target: {int(new_target)} deg",
                        (w // 2 - 350, h // 2),
                        cv2.FONT_HERSHEY_PLAIN,
                        2,
                        (0, 255, 0),
                        2
                    )
                else:
                    show_message = False
                    current_state["level_up"] = False

            cv2.imshow("Image", frame_to_show)
            key = cv2.waitKey(1) & 0xFF
            
            if key == ord('q'):
                break
            elif key == ord('l'):
                save_session(USER_ID, int(angle_target_forward), int(angle_target_backward), reps, level_up=False)
                
                if FORWARD_TILT:
                    if angle_target_forward + ANGLE_INCREMENT <= MAX_ANGLE_TARGET_FORWARD:
                        angle_target_forward += ANGLE_INCREMENT
                    else:
                        angle_target_forward = MIN_ANGLE_TARGET_FORWARD
                else:
                    if angle_target_backward + ANGLE_INCREMENT <= MAX_ANGLE_TARGET_BACKWARD:
                        angle_target_backward += ANGLE_INCREMENT
                    else:
                        angle_target_backward = MIN_ANGLE_TARGET_BACKWARD
                
                reps_last_session = reps
                reps = 0
                
                temp_img = img.copy()
                direction = "Forward" if FORWARD_TILT else "Backward"
                new_target = angle_target_forward if FORWARD_TILT else angle_target_backward
                cv2.putText(temp_img, f"Level Up! New {direction} target: {int(new_target)} deg",
                            (w // 2 - 350, h // 2),
                            cv2.FONT_HERSHEY_PLAIN, 3, (0, 255, 0), 3)
                cv2.imshow("Image", temp_img)
                cv2.waitKey(1500)
            
            elif key == ord('b'):
                save_session(USER_ID, int(angle_target_forward), int(angle_target_backward), reps, level_up=False)
                
                FORWARD_TILT = not FORWARD_TILT
                
                reps_last_session = reps
                reps = 0
                
                temp_img = img.copy()
                direction = "Forward" if FORWARD_TILT else "Backward"
                new_target = angle_target_forward if FORWARD_TILT else angle_target_backward
                cv2.putText(temp_img, f"Direction: {direction} | Target: {int(new_target)} deg",
                            (w // 2 - 300, h // 2),
                            cv2.FONT_HERSHEY_PLAIN, 3, (255, 165, 0), 3)
                cv2.imshow("Image", temp_img)
                cv2.waitKey(1000)
            
            if cv2.getWindowProperty("Image", cv2.WND_PROP_VISIBLE) < 1:
                break

    finally:
        print(f"\nSession complete: {reps} reps at Forward:{int(angle_target_forward)}° Backward:{int(angle_target_backward)}°")
        save_session(USER_ID, int(angle_target_forward), int(angle_target_backward), reps, level_up=False)
        cap.release()
        cv2.destroyAllWindows()
        quit_requested = True

if __name__ == "__main__":
    main()