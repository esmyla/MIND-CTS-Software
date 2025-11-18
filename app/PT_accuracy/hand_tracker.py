import cv2
import mediapipe as mp
import time
import sys
import math
import json
import os

# ----- Visual/logic config -----
ANGLE_TOLERANCE = 0.75      # degrees around target to trigger the ding
RESET_THRESHOLD = 4.0      # degrees near zero to re-arm the ding
LINE_COLOR = (0, 255, 0)    # green for the hand line (0->12)
VERT_COLOR = (0, 255, 255)  # yellow for vertical reference
TEXT_COLOR = (255, 0, 255)
HUD_COLOR = (255, 255, 255)

# ----- Progress persistence -----
STATE_FILE = "hand_tracker_state.json"
DEFAULT_STATE = {
    "angle_target": 30,   # start goal angle in degrees
    "reps_goal": 5,       # reps required for “Level Up”
}

MAX_ANGLE_TARGET = 60
MIN_ANGLE_TARGET = 30
REPS_GOAL_STEP = 5
MAX_REPS_GOAL = 20

def load_state(path: str) -> dict:
    if os.path.isfile(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            # sanity defaults
            data.setdefault("angle_target", DEFAULT_STATE["angle_target"])
            data.setdefault("reps_goal", DEFAULT_STATE["reps_goal"])
            return data
        except Exception:
            pass
    return DEFAULT_STATE.copy()

def save_state(path: str, data: dict) -> None:
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
    except Exception:
        pass

def ding():
    """
    Cross-platform-ish 'ding':
    - On Windows, use winsound.Beep.
    - Otherwise, try the terminal bell. (May depend on terminal settings.)
    """
    try:
        import winsound
        winsound.Beep(880, 200)  # frequency (Hz), duration (ms)
    except Exception:
        print('\a', end='', flush=True)

def main():
    state = load_state(STATE_FILE)
    angle_target = float(state.get("angle_target", DEFAULT_STATE["angle_target"]))
    reps_goal = int(state.get("reps_goal", DEFAULT_STATE["reps_goal"]))

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("Error: Could not open webcam. Check permissions or try a different device index (e.g., 1).")
        sys.exit(1)

    mpHands = mp.solutions.hands
    hands = mpHands.Hands(
        static_image_mode=False,
        max_num_hands=1,                # using 1 since you track a single hand
        min_detection_confidence=0.6,
        min_tracking_confidence=0.5
    )
    mpDraw = mp.solutions.drawing_utils

    # ---- Smaller drawing specs (half-sized visuals) ----
    landmark_spec = mpDraw.DrawingSpec(color=(80, 220, 100), thickness=1, circle_radius=1)
    connection_spec = mpDraw.DrawingSpec(color=(0, 180, 255), thickness=1, circle_radius=1)

    pTime = 0
    fingertip_ids = {4, 8, 12, 16, 20}

    armed = True
    reps = 0

    baseline_id0 = None

    try:
        while True:
            success, img = cap.read()
            if not success:
                continue

            img = cv2.flip(img, 1)
            imgRGB = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            results = hands.process(imgRGB)

            h, w, _ = img.shape

            # ----- Transparent vertical reference line -----
            vertical_x = w // 2
            overlay = img.copy()
            # Keep line thickness at 2, but blend it to transparency
            cv2.line(overlay, (vertical_x, 0), (vertical_x, h - 1), VERT_COLOR, 2)
            # alpha determines transparency of the line; 0.3 = 30% opaque
            cv2.addWeighted(overlay, 0.3, img, 0.7, 0, img)

            id0_xy = None
            id12_xy = None
            id9_xy = None
            angle_deg = None
            angle_deg_2 = None

            if results.multi_hand_landmarks:
                for handLms in results.multi_hand_landmarks:
                    # Draw smaller landmarks & connections
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
                            # Smaller fingertip markers (half-size: radius 2 instead of 4)
                            cv2.circle(img, (cx, cy), 2, (255, 0, 255), cv2.FILLED)

                        if idx == 0:
                            id0_xy = (cx, cy)
                        elif idx == 9:
                            id9_xy = (cx, cy)
                        elif idx == 12:
                            id12_xy = (cx, cy)

                    # If both points exist, draw line and compute angle
                    if id0_xy is not None and id12_xy is not None:
                        # Thinner line between wrist (0) and middle fingertip (12)
                        cv2.line(img, id0_xy, id12_xy, LINE_COLOR, 1)
                        # Smaller endpoint markers
                        cv2.circle(img, id0_xy, 1, LINE_COLOR, cv2.FILLED)
                        cv2.circle(img, id12_xy, 1, LINE_COLOR, cv2.FILLED)

                        dx = id12_xy[0] - id0_xy[0]
                        dy = id12_xy[1] - id0_xy[1]

                        # returns 0..pi/2
                        angle_rad = math.atan2(abs(dx), abs(dy))
                        angle_deg = math.degrees(angle_rad)

                    if id0_xy is not None and id9_xy is not None:
                        # Thinner line between wrist (0) and middle fingertip (12)
                        cv2.line(img, id0_xy, id9_xy, LINE_COLOR, 1)
                        # Smaller endpoint markers
                        cv2.circle(img, id0_xy, 1, LINE_COLOR, cv2.FILLED)
                        cv2.circle(img, id9_xy, 1, LINE_COLOR, cv2.FILLED)

                        dx2 = id9_xy[0] - id0_xy[0]
                        dy2 = id9_xy[1] - id0_xy[1]

                        # returns 0..pi/2
                        angle_rad_2 = math.atan2(abs(dx2), abs(dy2))
                        angle_deg_2 = math.degrees(angle_rad_2)


            # HUD: angle
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

            # Triggering & level up logic
            if angle_deg is not None and angle_deg_2 is not None:
                # Trigger once when close to target
                if armed and (angle_deg > angle_target and (abs(angle_deg_2 - angle_deg) < 10)):
                    ding()
                    armed = False
                    reps += 1

                    cv2.putText(img, "DING!", (w // 2 - 70, 120),
                                cv2.FONT_HERSHEY_PLAIN, 3, (0, 200, 255), 3)

                    # Level up logic
                    if reps >= reps_goal:
                        cv2.putText(
                            img, "Level Up",
                            (w // 2 - 140, h // 2),
                            cv2.FONT_HERSHEY_PLAIN, 5, (0, 0, 255), 5
                        )
                        cv2.imshow("Image", img)
                        cv2.waitKey(1200)  # brief celebration

                        reps = 0
                        # Increase reps goal by step up to MAX_REPS_GOAL, then bump angle
                        if reps_goal + REPS_GOAL_STEP <= MAX_REPS_GOAL:
                            reps_goal += REPS_GOAL_STEP
                        else:
                            reps_goal = DEFAULT_STATE["reps_goal"]
                            # Increase angle target in steps, wrap after MAX_ANGLE_TARGET
                            if angle_target + 5 <= MAX_ANGLE_TARGET:
                                angle_target += 5
                            else:
                                angle_target = MIN_ANGLE_TARGET

                        state["angle_target"] = angle_target
                        state["reps_goal"] = reps_goal
                        save_state(STATE_FILE, state)

                if (abs(angle_deg_2 - angle_deg) > 10):
                    warn_text = "Keep your hand straight."
                    # Place the text near the top center but keep it on-screen
                    x_text = max(10, w // 2 - 150)
                    cv2.putText(img, warn_text, (x_text, 80),
                    cv2.FONT_HERSHEY_PLAIN, 1.5, (0, 0, 255), 2)   
                    if reps < 0:
                        reps = 0
                        
                # Re-arm once near zero
                if (not armed) and angle_deg <= RESET_THRESHOLD:
                    armed = True
                    # When re-armed, update the baseline to the current wrist position if available
                    if 'id0_xy' in locals() and id0_xy is not None:
                        baseline_id0 = id0_xy
                    
                if ('id0_xy' in locals() and 'id12_xy' in locals()
                    and id0_xy is not None and id12_xy is not None):

                    # If no baseline yet (e.g., first valid detection), set it now.
                    if baseline_id0 is None:
                        baseline_id0 = id0_xy

                    # Current "hand length" in pixels from wrist(0) to middle fingertip(12)
                    hand_len = math.hypot(id12_xy[0] - id0_xy[0], id12_xy[1] - id0_xy[1])

                    if hand_len > 0:
                        # How far the wrist moved from the baseline
                        wrist_drift = math.hypot(id0_xy[0] - baseline_id0[0], id0_xy[1] - baseline_id0[1])
                        
                        # If wrist drift exceeds a third of the 0->12 distance, warn and reset reps
                        if wrist_drift > (hand_len / 3.0):
                            armed = False  # Disarm if wrist drift detected
                            warn_text = "Try not to move your arm, just your wrist."
                            # Place the text near the top center but keep it on-screen
                            x_text = max(10, w // 2 - 320)
                            cv2.putText(img, warn_text, (x_text, 50),
                            cv2.FONT_HERSHEY_PLAIN, 1.5, (0, 0, 255), 2)   
                            
            
            # HUD: target angle and reps
            cv2.putText(img, f"Target: {int(angle_target)} deg", (10, 160),
                        cv2.FONT_HERSHEY_PLAIN, 2, HUD_COLOR, 2)
            cv2.putText(img, f"Reps: {reps}/{reps_goal}", (10, 200),
                        cv2.FONT_HERSHEY_PLAIN, 2, HUD_COLOR, 2)

            cv2.imshow("Image", img)
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                break
            # Check if the window was closed by the user
            if cv2.getWindowProperty("Image", cv2.WND_PROP_VISIBLE) < 1:
                break

    finally:
        cap.release()
        cv2.destroyAllWindows()

if __name__ == "__main__":
    main()