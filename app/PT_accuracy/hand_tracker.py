import cv2
import mediapipe as mp
import time
import sys

def main():
    # Open a connection to the default camera (0).
    cap = cv2.VideoCapture(0)

    # Check if the camera opened successfully.
    if not cap.isOpened():
        print("Error: Could not open webcam. Check permissions or try a different device index (e.g., 1).")
        sys.exit(1)

    # Initialize MediaPipe Hands with tuned parameters for real-time video.
    mpHands = mp.solutions.hands
    hands = mpHands.Hands(
        static_image_mode=False,       # Better for video streams
        max_num_hands=2,               # Detect up to two hands
        min_detection_confidence=0.6,  # Detection threshold
        min_tracking_confidence=0.5    # Tracking threshold
    )
    mpDraw = mp.solutions.drawing_utils

    pTime = 0  # previous frame time

    # Fingertip landmark IDs per MediaPipe's hand landmark model.
    # 4 = Thumb tip, 8 = Index tip, 12 = Middle tip, 16 = Ring tip, 20 = Pinky tip
    fingertip_ids = {4, 8, 12, 16, 20}

    try:
        while True:
            success, img = cap.read()
            if not success:
                # If a frame wasn't captured, skip this iteration.
                # This can happen sporadically depending on the camera driver.
                continue

            # Mirror to act like a selfie camera.
            img = cv2.flip(img, 1)

            # Convert BGR (OpenCV) to RGB (MediaPipe).
            imgRGB = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

            # Run the hand landmark detection.
            results = hands.process(imgRGB)

            # If hands are detected...
            if results.multi_hand_landmarks:
                for handLms in results.multi_hand_landmarks:
                    # Draw all landmarks and connections on the original BGR frame.
                    mpDraw.draw_landmarks(img, handLms, mpHands.HAND_CONNECTIONS)

                    # Iterate over each landmark and draw circles for fingertips.
                    h, w, _ = img.shape
                    for idx, lm in enumerate(handLms.landmark):
                        cx, cy = int(lm.x * w), int(lm.y * h)

                        # OPTIONAL: Uncomment to debug landmark locations in console.
                        # print(idx, cx, cy)

                        # Highlight fingertip landmarks.
                        if idx in fingertip_ids:
                            cv2.circle(img, (cx, cy), 10, (255, 0, 255), cv2.FILLED)

            # Compute FPS safely.
            cTime = time.time()
            dt = cTime - pTime
            fps = 1.0 / dt if dt > 0 else 0.0
            pTime = cTime

            # Render FPS.
            cv2.putText(
                img, f"{int(fps)}", (10, 70),
                cv2.FONT_HERSHEY_PLAIN, 3, (255, 0, 255), 3
            )

            # Display the frame.
            cv2.imshow("Image", img)

            # Wait for keypress (1 ms) and check for 'q' to quit.
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                break

    finally:
        # Ensure resources are released even if an exception occurs.
        cap.release()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()