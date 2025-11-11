import cv2
import mediapipe as mp
import time
import sys
import math

# ----- Config -----
ANGLE_TOLERANCE = 0.75    # degrees around target to trigger the ding
RESET_THRESHOLD = 2.0     # degrees near zero to re-arm the ding
LINE_COLOR = (0, 255, 0)  # green for the hand line (0->12)
VERT_COLOR = (0, 255, 255)  # yellow for vertical reference
TEXT_COLOR = (255, 0, 255)

#get this data from the user's past session data
ANGLE_TARGET = 30   # degrees

def ding():
    """
    Cross-platform-ish 'ding':
    - On Windows, use winsound.Beep.
    - Otherwise, try the terminal bell. (May depend on terminal settings.)
    """
    try:
        import winsound
        winsound.Beep(880, 180)  # frequency (Hz), duration (ms)
    except Exception:
        # Fallback: terminal bell (might be silenced depending on terminal)
        print('\a', end='', flush=True)

def main():
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("Error: Could not open webcam. Check permissions or try a different device index (e.g., 1).")
        sys.exit(1)

    mpHands = mp.solutions.hands
    hands = mpHands.Hands(
        static_image_mode=False,
        max_num_hands=1,
        min_detection_confidence=0.6,
        min_tracking_confidence=0.5
    )
    mpDraw = mp.solutions.drawing_utils

    pTime = 0
    fingertip_ids = {4, 8, 12, 16, 20}

    # State for one-shot ding
    ding_played = False

    try:
        while True:
            success, img = cap.read()
            if not success:
                continue

            img = cv2.flip(img, 1)
            imgRGB = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            results = hands.process(imgRGB)

            h, w, _ = img.shape

            # --- Draw vertical reference line (center of the frame) ---
            vertical_x = w // 2
            cv2.line(img, (vertical_x, 0), (vertical_x, h - 1), VERT_COLOR, 2)

            # For angle calculation and drawing line between ID 0 and 12
            id0_xy = None
            id12_xy = None

            if results.multi_hand_landmarks:
                for handLms in results.multi_hand_landmarks:
                    # Draw landmarks
                    mpDraw.draw_landmarks(img, handLms, mpHands.HAND_CONNECTIONS)

                    # Collect 0 and 12; also mark fingertips for clarity
                    for idx, lm in enumerate(handLms.landmark):
                        cx, cy = int(lm.x * w), int(lm.y * h)

                        if idx in fingertip_ids:
                            cv2.circle(img, (cx, cy), 10, (255, 0, 255), cv2.FILLED)

                        if idx == 0:
                            id0_xy = (cx, cy)
                        elif idx == 12:
                            id12_xy = (cx, cy)

                    # If both points exist, draw line and compute angle
                    if id0_xy is not None and id12_xy is not None:
                        # Draw line between wrist (0) and middle fingertip (12)
                        cv2.line(img, id0_xy, id12_xy, LINE_COLOR, 3)
                        cv2.circle(img, id0_xy, 6, LINE_COLOR, cv2.FILLED)
                        cv2.circle(img, id12_xy, 6, LINE_COLOR, cv2.FILLED)

                        dx = id12_xy[0] - id0_xy[0]
                        dy = id12_xy[1] - id0_xy[1]

                        # Compute angle between this line and the vertical axis.
                        # Angle to vertical in [0..90] = arctan(|dx| / |dy|)
                        # Handle dy == 0 safely using atan2
                        angle_rad = math.atan2(abs(dx), abs(dy))  # returns 0..pi/2
                        angle_deg = math.degrees(angle_rad)

                        # Show the angle on screen
                        cv2.putText(
                            img, f"Angle: {angle_deg:4.1f} deg",
                            (10, 120), cv2.FONT_HERSHEY_PLAIN, 2, TEXT_COLOR, 2
                        )

                        # ----- One-shot ding at 30 degrees, re-arm at ~0 -----
                        if (not ding_played) and (abs(angle_deg - ANGLE_TARGET) <= ANGLE_TOLERANCE):
                            ding()
                            ding_played = True
                            reps += 1

                        # Reset once angle is back near 0 (to allow future dings)
                        if ding_played and angle_deg <= RESET_THRESHOLD:
                            ding_played = False

            # FPS
            cTime = time.time()
            dt = cTime - pTime
            fps = 1.0 / dt if dt > 0 else 0.0
            pTime = cTime

            cv2.putText(img, f"{int(fps)}", (10, 70),
                        cv2.FONT_HERSHEY_PLAIN, 3, TEXT_COLOR, 3)

            cv2.imshow("Image", img)
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                break

    finally:
        cap.release()
        cv2.destroyAllWindows()

if __name__ == "__main__":
    main()