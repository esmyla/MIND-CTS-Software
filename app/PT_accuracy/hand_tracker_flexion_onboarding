"""
Wrist Flexion Onboarding Calibration Application
=================================================
This application calibrates a new user's starting angles by measuring their
maximum range of motion in both forward and backward directions.

Process:
1. Forward flexion: 5 attempts, average - 10° = starting forward angle
2. Backward extension: 5 attempts, average - 5° = starting backward angle
3. Saves calibrated angles to Supabase database

Dependencies:
- OpenCV (cv2): Video capture and image processing
- MediaPipe: Hand landmark detection
- Supabase: Cloud database for persistent storage
"""

import cv2
import mediapipe as mp
import time
import sys
import math
import os
from supabase import create_client, Client
from datetime import datetime

# ===================================================================
# SUPABASE CONFIGURATION
# ===================================================================
SUPABASE_URL = os.getenv("SUPABASE_URL", "https://cmmumwwzydfebahhgfyi.supabase.co")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNtbXVtd3d6eWRmZWJhaGhnZnlpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI4MDkwNTAsImV4cCI6MjA3ODM4NTA1MH0.zJBi0owKoaycNzmtAm9_5ZsUwXIUmxAGuCy0AhsaoZc")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# ===================================================================
# CALIBRATION CONSTANTS
# ===================================================================
STABILIZATION_THRESHOLD = 4.0   # Degrees of variation allowed for "stable"
STABILIZATION_TIME = 2.0        # Seconds to hold stable before recording
NUM_ATTEMPTS = 5                # Number of calibration attempts per direction
FORWARD_OFFSET = 10             # Degrees to subtract from forward average
BACKWARD_OFFSET = 5             # Degrees to subtract from backward average

# Visual constants
LINE_COLOR = (0, 255, 0)
TEXT_COLOR = (0, 0, 255)
SUCCESS_COLOR = (0, 255, 0)
WARNING_COLOR = (0, 165, 255)

# User configuration
HANDEDNESS = "Right"  # "Right" or "Left"

# ===================================================================
# AUDIO FEEDBACK
# ===================================================================
def ding():
    """Play a system beep to indicate successful recording"""
    print("\a", end="", flush=True)

# ===================================================================
# DATABASE FUNCTIONS
# ===================================================================
def save_calibration(user_id: str, angle_forward: int, angle_backward: int) -> None:
    """
    Save calibrated starting angles to Supabase.
    
    Args:
        user_id: User's UUID
        angle_forward: Calibrated forward flexion starting angle
        angle_backward: Calibrated backward extension starting angle
    """
    try:
        record = {
            "user_id": user_id,
            "session": 0,  # Session 0 indicates initial calibration
            "degree_forward": angle_forward,
            "degree_backward": angle_backward,
            "repetitions": 0,
            "level_up": False,
            "created_at": datetime.utcnow().isoformat()
        }
        
        response = supabase.table("flexion").insert(record).execute()
        
        if response.data:
            print(f"✓ Calibration saved: Forward={angle_forward}°, Backward={angle_backward}°")
        
    except Exception as e:
        print(f"✗ Error saving calibration: {e}")

# ===================================================================
# ANGLE CALCULATION
# ===================================================================
def calculate_angle(id0_xy, id12_xy):
    """
    Calculate wrist flexion angle from wrist to middle fingertip.
    
    Args:
        id0_xy: (x, y) coordinates of wrist (landmark 0)
        id12_xy: (x, y) coordinates of middle fingertip (landmark 12)
    
    Returns:
        float: Angle in degrees from vertical
    """
    if id0_xy is None or id12_xy is None:
        return None
    
    dx = id12_xy[0] - id0_xy[0]
    dy = id12_xy[1] - id0_xy[1]
    
    angle_rad = math.atan2(dx, dy)
    angle_deg = 180 - math.degrees(angle_rad)
    
    return angle_deg

# ===================================================================
# CALIBRATION STATE MACHINE
# ===================================================================
class CalibrationState:
    def __init__(self, direction, attempt_num):
        self.direction = direction  # "forward" or "backward"
        self.attempt_num = attempt_num
        self.stable_start_time = None
        self.stable_angle = None
        self.is_stable = False
        self.recorded = False
        self.recorded_angle = None
        self.angle_history = []  # For tracking stability
        self.max_history_size = 30  # ~1 second at 30fps
    
    def update(self, current_angle):
        """
        Update calibration state with new angle reading.
        
        Returns:
            bool: True if angle was successfully recorded
        """
        if current_angle is None or self.recorded:
            return False
        
        # Add to history for stability check
        self.angle_history.append(current_angle)
        if len(self.angle_history) > self.max_history_size:
            self.angle_history.pop(0)
        
        # Need enough history to check stability
        if len(self.angle_history) < 10:
            return False
        
        # Check if angle is stable (within threshold)
        recent_angles = self.angle_history[-10:]
        angle_range = max(recent_angles) - min(recent_angles)
        
        if angle_range <= STABILIZATION_THRESHOLD:
            # Angle is stable
            if not self.is_stable:
                # Just became stable
                self.is_stable = True
                self.stable_start_time = time.time()
                self.stable_angle = sum(recent_angles) / len(recent_angles)
            else:
                # Check if held stable long enough
                if time.time() - self.stable_start_time >= STABILIZATION_TIME:
                    # Record the angle!
                    self.recorded_angle = self.stable_angle
                    self.recorded = True
                    ding()
                    return True
        else:
            # Lost stability, reset
            self.is_stable = False
            self.stable_start_time = None
            self.stable_angle = None
        
        return False
    
    def get_time_held(self):
        """Get how long angle has been stable"""
        if self.is_stable and self.stable_start_time:
            return time.time() - self.stable_start_time
        return 0.0
    
    def get_progress_bar(self, width=200):
        """Generate a visual progress bar for stability timer"""
        if not self.is_stable:
            return "Not stable"
        
        progress = min(1.0, self.get_time_held() / STABILIZATION_TIME)
        filled = int(progress * width)
        bar = "█" * filled + "░" * (width - filled)
        return f"{bar} {progress*100:.0f}%"

# ===================================================================
# MAIN CALIBRATION FUNCTION
# ===================================================================
def main():
    """Main calibration loop"""
    
    # User ID - replace with actual UUID
    USER_ID = "stephen-uuid-1234-5678-9012-abcdefabcdef"
    
    # Initialize webcam
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("Error: Could not open webcam.")
        sys.exit(1)
    
    # Initialize MediaPipe
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
    
    # Calibration data storage
    forward_angles = []
    backward_angles = []
    
    # Start with forward calibration
    current_phase = "forward"
    attempt_num = 1
    state = CalibrationState("forward", 1)
    
    # Show initial instructions
    show_instructions = True
    instructions_shown_time = time.time()
    
    try:
        while True:
            success, img = cap.read()
            if not success:
                continue
            
            img = cv2.flip(img, 1)
            imgRGB = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            results = hands.process(imgRGB)
            
            h, w, _ = img.shape
            
            # Draw vertical reference line
            vertical_x = w // 2
            cv2.line(img, (vertical_x, 0), (vertical_x, h - 1), (0, 255, 255), 1)
            
            # Extract landmarks and calculate angle
            id0_xy = None
            id12_xy = None
            current_angle = None
            
            if results.multi_hand_landmarks:
                for handLms in results.multi_hand_landmarks:
                    mpDraw.draw_landmarks(
                        img, handLms, mpHands.HAND_CONNECTIONS,
                        landmark_drawing_spec=landmark_spec,
                        connection_drawing_spec=connection_spec
                    )
                    
                    for idx, lm in enumerate(handLms.landmark):
                        cx, cy = int(lm.x * w), int(lm.y * h)
                        
                        if idx == 0:
                            id0_xy = (cx, cy)
                        elif idx == 12:
                            id12_xy = (cx, cy)
                    
                    if id0_xy and id12_xy:
                        cv2.line(img, id0_xy, id12_xy, LINE_COLOR, 2)
                        current_angle = calculate_angle(id0_xy, id12_xy)
            
            # Show initial instructions
            if show_instructions and time.time() - instructions_shown_time < 20.0:
                instruction_text = [
                    "WRIST FLEXION CALIBRATION",
                    "",
                    "We'll measure your maximum range of motion",
                    "in both directions to set your starting angles.",
                    "",
                    "First: FORWARD flexion (fingers toward palm)",
                    "Then: BACKWARD extension (fingers away from palm)",
                    "",
                    "Hold each position steady for 2 seconds.",
                    "Press 's' to start..."
                ]
                
                y_offset = 150
                for line in instruction_text:
                    cv2.putText(img, line, (50, y_offset),
                               cv2.FONT_HERSHEY_PLAIN, 1.5, TEXT_COLOR, 2)
                    y_offset += 30
                
            elif not show_instructions:
                # Main calibration display
                
                # Show current angle
                if current_angle is not None:
                    cv2.putText(img, f"Angle: {current_angle:.1f}°",
                               (10, 40), cv2.FONT_HERSHEY_PLAIN, 2, TEXT_COLOR, 2)
                
                # Show phase and attempt
                phase_text = "FORWARD" if current_phase == "forward" else "BACKWARD"
                cv2.putText(img, f"{phase_text} Calibration - Attempt {attempt_num}/{NUM_ATTEMPTS}",
                           (10, 80), cv2.FONT_HERSHEY_PLAIN, 2, TEXT_COLOR, 2)
                
                # Show instruction
                if current_phase == "forward":
                    if HANDEDNESS == "Right":
                        instruction = "Tilt your wrist FORWARD (fingers LEFT) as far as comfortable"
                    else:
                        instruction = "Tilt your wrist FORWARD (fingers RIGHT) as far as comfortable"
                else:
                    if HANDEDNESS == "Right":
                        instruction = "Tilt your wrist BACKWARD (fingers RIGHT) as far as comfortable"
                    else:
                        instruction = "Tilt your wrist BACKWARD (fingers LEFT) as far as comfortable"
                
                cv2.putText(img, instruction,
                           (10, 120), cv2.FONT_HERSHEY_PLAIN, 1.1, WARNING_COLOR, 2)
                
                # Update calibration state
                if current_angle is not None:
                    if state.update(current_angle):
                        # Successfully recorded an angle
                        if current_phase == "forward":
                            forward_angles.append(state.recorded_angle)
                            print(f"Forward attempt {attempt_num}: {state.recorded_angle:.1f}°")
                        else:
                            backward_angles.append(state.recorded_angle)
                            print(f"Backward attempt {attempt_num}: {state.recorded_angle:.1f}°")
                        
                        # Check if we need to move to next attempt or phase
                        if attempt_num < NUM_ATTEMPTS:
                            attempt_num += 1
                            state = CalibrationState(current_phase, attempt_num)
                            
                            # Brief pause with success message
                            temp_img = img.copy()
                            cv2.putText(temp_img, "RECORDED! Return to neutral position...",
                                       (w//2 - 250, h//2), cv2.FONT_HERSHEY_PLAIN, 2, SUCCESS_COLOR, 3)
                            cv2.imshow("Calibration", temp_img)
                            cv2.waitKey(2000)
                        else:
                            # Phase complete
                            if current_phase == "forward":
                                # Move to backward calibration
                                current_phase = "backward"
                                attempt_num = 1
                                state = CalibrationState("backward", 1)
                                
                                # Show transition message
                                temp_img = img.copy()
                                cv2.putText(temp_img, "Forward calibration complete!",
                                           (w//2 - 200, h//2 - 30), cv2.FONT_HERSHEY_PLAIN, 2, SUCCESS_COLOR, 3)
                                cv2.putText(temp_img, "Now we'll calibrate BACKWARD motion...",
                                           (w//2 - 250, h//2 + 30), cv2.FONT_HERSHEY_PLAIN, 2, TEXT_COLOR, 2)
                                cv2.imshow("Calibration", temp_img)
                                cv2.waitKey(3000)
                            else:
                                # All done!
                                break
                
                # Show stability indicator
                if state.is_stable:
                    time_held = state.get_time_held()
                    progress = min(100, (time_held / STABILIZATION_TIME) * 100)
                    cv2.putText(img, f"HOLD STEADY: {progress:.0f}%",
                               (10, 160), cv2.FONT_HERSHEY_PLAIN, 2, SUCCESS_COLOR, 2)
                    
                    # Progress bar
                    bar_width = 400
                    bar_height = 30
                    bar_x = (w - bar_width) // 2
                    bar_y = 200
                    
                    # Background
                    cv2.rectangle(img, (bar_x, bar_y), (bar_x + bar_width, bar_y + bar_height),
                                 TEXT_COLOR, 2)
                    
                    # Progress fill
                    fill_width = int(bar_width * progress / 100)
                    cv2.rectangle(img, (bar_x, bar_y), (bar_x + fill_width, bar_y + bar_height),
                                 SUCCESS_COLOR, -1)
                else:
                    cv2.putText(img, "Stabilizing...",
                               (10, 160), cv2.FONT_HERSHEY_PLAIN, 2, WARNING_COLOR, 2)
                
                # Show recorded angles so far
                if forward_angles:
                    cv2.putText(img, f"Forward attempts: {', '.join([f'{a:.1f}' for a in forward_angles])}",
                               (10, h - 60), cv2.FONT_HERSHEY_PLAIN, 1.2, TEXT_COLOR, 1)
                
                if backward_angles:
                    cv2.putText(img, f"Backward attempts: {', '.join([f'{a:.1f}' for a in backward_angles])}",
                               (10, h - 30), cv2.FONT_HERSHEY_PLAIN, 1.2, TEXT_COLOR, 1)
            
            cv2.imshow("Calibration", img)
            key = cv2.waitKey(1) & 0xFF
            
            if key == ord('q'):
                print("Calibration cancelled")
                return
            elif key == ord('s') and show_instructions:
                show_instructions = False
            
            if cv2.getWindowProperty("Calibration", cv2.WND_PROP_VISIBLE) < 1:
                break
        
        # Calculate final calibrated angles
        if len(forward_angles) == NUM_ATTEMPTS and len(backward_angles) == NUM_ATTEMPTS:
            avg_forward = sum(forward_angles) / len(forward_angles)
            avg_backward = sum(backward_angles) / len(backward_angles)
            
            # Apply offsets
            calibrated_forward = max(25, int(avg_forward - FORWARD_OFFSET))
            calibrated_backward = max(10, int(avg_backward - BACKWARD_OFFSET))
            
            print(f"\n=== CALIBRATION COMPLETE ===")
            print(f"Forward attempts: {[f'{a:.1f}' for a in forward_angles]}")
            print(f"Average: {avg_forward:.1f}° → Starting angle: {calibrated_forward}°")
            print(f"\nBackward attempts: {[f'{a:.1f}' for a in backward_angles]}")
            print(f"Average: {avg_backward:.1f}° → Starting angle: {calibrated_backward}°")
            
            # Save to database
            save_calibration(USER_ID, calibrated_forward, calibrated_backward)
            
            # Show final results
            img = cv2.imread(cv2.samples.findFile('lena.jpg')) if False else img
            img[:] = (50, 50, 50)  # Dark background
            
            results_text = [
                "CALIBRATION COMPLETE!",
                "",
                f"Your starting angles:",
                f"  Forward:  {calibrated_forward}°",
                f"  Backward: {calibrated_backward}°",
                "",
                "These angles have been saved.",
                "You can now start training!",
                "",
                "Press any key to exit..."
            ]
            
            y_offset = 150
            for line in results_text:
                text_size = cv2.getTextSize(line, cv2.FONT_HERSHEY_PLAIN, 2, 2)[0]
                x_pos = (w - text_size[0]) // 2
                cv2.putText(img, line, (x_pos, y_offset),
                           cv2.FONT_HERSHEY_PLAIN, 2, SUCCESS_COLOR if "COMPLETE" in line else TEXT_COLOR, 2)
                y_offset += 40
            
            cv2.imshow("Calibration", img)
            cv2.waitKey(0)
    
    finally:
        cap.release()
        cv2.destroyAllWindows()

if __name__ == "__main__":
    main()