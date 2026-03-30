#TODO:
# Make an  onboarding version of the hand flexion app that has user tilt forward their as far as they can. Once they angle of flexion has stabalized (within +/- 4 degree range held for atleast two seconds), record that number. Then have them do that again 5 times, take the average of the 5 attempts, subtract 10, and set that as their starting angle in the supabase database
# then after that, test their backward motion the same way, take that average, subtract 5, and set that as their starting backward angle in the database


"""
Wrist Flexion Tracking Application with Supabase Integration
============================================================
This application tracks wrist flexion angles using MediaPipe hand tracking
and stores progress data in a Supabase database. Users complete repetitions
at target angles in both forward and backward directions, with each session 
tracking total reps and showing the previous session's count as a soft goal.

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
import json
import os
from supabase import create_client, Client
from typing import Optional
from datetime import datetime

# ===================================================================
# VISUAL AND LOGIC CONFIGURATION
# ===================================================================
# These constants control the sensitivity and appearance of the tracker

ANGLE_TOLERANCE = 0.75      # Degrees around target angle to trigger success "ding"
                             # (e.g., if target is 30°, success triggers at 29.25-30.75°)

RESET_THRESHOLD = 4.0       # Degrees near zero (straight wrist) to re-arm the system
                             # User must return to this range before next rep counts

LINE_COLOR = (0, 255, 0)    # Green BGR color for the hand line (wrist->middle finger)
VERT_COLOR = (0, 255, 255)  # Yellow BGR color for vertical reference line
TEXT_COLOR = (255, 0, 255)  # Magenta BGR color for angle text display
HUD_COLOR = (255, 255, 255) # White BGR color for HUD (heads-up display) text

# ===================================================================
# SUPABASE CONFIGURATION
# ===================================================================
# Configure your Supabase project credentials here or via environment variables
# Get these from your Supabase project settings -> API

SUPABASE_URL = os.getenv("SUPABASE_URL", "https://cmmumwwzydfebahhgfyi.supabase.co")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNtbXVtd3d6eWRmZWJhaGhnZnlpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI4MDkwNTAsImV4cCI6MjA3ODM4NTA1MH0.zJBi0owKoaycNzmtAm9_5ZsUwXIUmxAGuCy0AhsaoZc")

# Initialize the Supabase client for database operations
supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# ===================================================================
# PROGRESSION SYSTEM CONSTANTS
# ===================================================================
# Define the default starting state and limits for the progression system

DEFAULT_STATE = {
    "angle_target_forward": 30,    # Starting target angle for forward flexion
    "angle_target_backward": 15,   # Starting target angle for backward flexion
    "reps_last_session": 0,        # Reps from previous session (used as soft goal)
}

# Angle target boundaries
MAX_ANGLE_TARGET_FORWARD = 70     # Maximum flexion angle target (safety limit)
MIN_ANGLE_TARGET_FORWARD = 25     # Minimum flexion angle target (starting difficulty)
MAX_ANGLE_TARGET_BACKWARD = 50    # Maximum extension angle target (safety limit)
MIN_ANGLE_TARGET_BACKWARD = 10    # Minimum extension angle target (starting difficulty)

# Angle increment when user manually levels up
ANGLE_INCREMENT = 5       # Degrees to add to target when leveling up
NUM_REPS_TO_LEVEL_UP = 5  # Number of reps needed to automatically level up

# Variable setting for handedness
HANDEDNESS = "Left"      # "Right" or "Left" hand tracking
FORWARD_TILT = True   # True = fingers bend toward palm, False = backward tilt

# ===================================================================
# AUDIO FEEDBACK FUNCTION
# ===================================================================

def ding():
    """
    Provide audio feedback when a successful rep is completed.
    
    Prints a bell character (\a) which produces a system beep on most platforms.
    This gives immediate feedback to the user without requiring them to look
    at the screen.
    """
    print("\a", end="", flush=True)

# ===================================================================
# DATABASE QUERY FUNCTIONS
# ===================================================================

def get_current_session(user_id: str) -> int:
    """
    Retrieve the most recent session number for a specific user.
    
    Sessions are used to group sets of exercises together. Each training
    session gets a unique incrementing number. This function finds the highest
    session number currently in the database for the given user.
    
    Args:
        user_id (str): The UUID of the user to query
        
    Returns:
        int: The current session number, or 0 if no sessions exist yet
        
    Database Query:
        SELECT session FROM flexion 
        WHERE user_id = ? 
        ORDER BY session DESC 
        LIMIT 1
    """
    try:
        # Query Supabase for the latest session number
        response = supabase.table("flexion")\
            .select("session")\
            .eq("user_id", user_id)\
            .order("session", desc=True)\
            .limit(1)\
            .execute()
        
        # If data exists, return the session number
        if response.data:
            return response.data[0]["session"]
        
        # No previous sessions found - this is a new user
        return 0
    
    except Exception as e:
        print(f"Error getting current session: {e}")
        return 0  # Default to session 0 on error

def get_last_session_reps(user_id: str) -> int:
    """
    Retrieve the total number of reps from the user's previous session.
    
    This value is used as a "soft goal" - a benchmark to beat rather than
    a hard requirement. It helps users track their progress session-to-session.
    
    Args:
        user_id (str): The UUID of the user to query
        
    Returns:
        int: Number of reps from the last session, or 0 if no previous session
        
    Database Query:
        SELECT repetitions FROM flexion 
        WHERE user_id = ? 
        ORDER BY session DESC 
        LIMIT 1
    """
    try:
        # Query for the most recent session's rep count
        response = supabase.table("flexion")\
            .select("repetitions")\
            .eq("user_id", user_id)\
            .order("session", desc=True)\
            .limit(1)\
            .execute()
        
        # If data exists, return the rep count
        if response.data:
            return response.data[0]["repetitions"]
        
        # No previous session found
        return 0
    
    except Exception as e:
        print(f"Error getting last session reps: {e}")
        return 0

def load_state(user_id: str) -> dict:
    """
    Load the most recent training state from Supabase for a given user.
    
    This function retrieves the user's latest progress including their current
    target angles for both forward and backward flexion, and the rep count from 
    their last session (used as a soft goal). If no data exists (new user), 
    returns default starting values.
    
    Args:
        user_id (str): The UUID of the user whose state to load
        
    Returns:
        dict: Dictionary containing:
            - angle_target_forward (int): Current target forward flexion angle
            - angle_target_backward (int): Current target backward flexion angle
            - reps_last_session (int): Reps from previous session (soft goal)
            - session (int): Current session number (for reference)
            
    Database Query:
        SELECT * FROM flexion 
        WHERE user_id = ? 
        ORDER BY created_at DESC 
        LIMIT 1
    """
    try:
        # Query for the most recent record for this user
        response = supabase.table("flexion")\
            .select("*")\
            .eq("user_id", user_id)\
            .order("created_at", desc=True)\
            .limit(1)\
            .execute()
        
        # If we found a record, parse it into our state format
        if response.data:
            latest = response.data[0]
            return {
                "angle_target_forward": latest.get("degree_forward", DEFAULT_STATE["angle_target_forward"]),
                "angle_target_backward": latest.get("degree_backward", DEFAULT_STATE["angle_target_backward"]),
                "reps_last_session": latest["repetitions"],
                "session": latest["session"],
            }
        
        # No data found - user is new, return default starting state
        return {**DEFAULT_STATE, "session": 0}
    
    except Exception as e:
        print(f"Error loading state from Supabase: {e}")
        # On error, return defaults so the app can still run
        return {**DEFAULT_STATE, "session": 0}

def save_session(user_id: str, angle_target_forward: int, angle_target_backward: int, 
                reps_completed: int, level_up: bool = False) -> None:
    """
    Save a completed training session to Supabase.
    
    This function creates a new record in the flexion table representing
    a complete training session. Each save creates a new row (not an update)
    to maintain a complete history of the user's progress over time.
    
    Args:
        user_id (str): The UUID of the user
        angle_target_forward (int): The forward target angle used during this session
        angle_target_backward (int): The backward target angle used during this session
        reps_completed (int): Total number of successful reps in this session
        level_up (bool): Whether this session ended with a level up
                         If True, increments the session number
        
    Database Operation:
        INSERT INTO flexion (user_id, session, degree_forward, degree_backward, 
                           repetitions, level_up, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        
    Note: This function INSERTS new rows rather than UPDATING existing ones,
          creating a complete audit trail of all training sessions.
    """
    try:
        # Get the current session number
        current_session = get_current_session(user_id)
        
        # If this is a level up, start a new session; otherwise continue current
        if level_up:
            current_session += 1
        else:
            # For same session, just increment (new workout within same difficulty)
            current_session += 1
        
        # Prepare the record to insert into the database
        record = {
            "user_id": user_id,
            "session": current_session,
            "degree_forward": angle_target_forward,
            "degree_backward": angle_target_backward,
            "repetitions": reps_completed,
            "level_up": level_up,
            "created_at": datetime.utcnow().isoformat()  # UTC timestamp
        }
        
        # Insert the record into Supabase
        response = supabase.table("flexion").insert(record).execute()
        
        # Confirm success
        if response.data:
            print(f"✓ Session saved: {reps_completed} reps at {angle_target_forward}°F/{angle_target_backward}°B (Session #{current_session})")
        
    except Exception as e:
        print(f"✗ Error saving session to Supabase: {e}")
        # Note: We don't raise the exception - allows app to continue even if save fails

# ===================================================================
# MAIN APPLICATION
# ===================================================================

def main():
    """
    Main application loop for wrist flexion tracking.
    
    This function:
    1. Loads user state from Supabase (or uses defaults for new users)
    2. Initializes webcam and MediaPipe hand tracking
    3. Continuously processes video frames to detect hand landmarks
    4. Calculates wrist flexion angle from landmarks
    5. Counts successful reps when target angle is reached
    6. Provides visual feedback and warnings
    7. Saves session data when user exits
    
    Controls:
    - 'q': Quit and save session
    - 'l': Level up (increase target angle by 5°)
    - 'b': Toggle between forward and backward tilt
    - Window close button: Quit and save session
    """
    
    # ===================================================================
    # USER CONFIGURATION - CHANGE THIS TO YOUR USER UUID
    # ===================================================================

    # Replace with the actual UUID from your Supabase auth system
    USER_ID = "stephen-uuid-1234-5678-9012-abcdefabcdef"
    
    # Load user's state from Supabase
    state = load_state(USER_ID)
    angle_target_forward = float(state.get("angle_target_forward", DEFAULT_STATE["angle_target_forward"]))
    angle_target_backward = float(state.get("angle_target_backward", DEFAULT_STATE["angle_target_backward"]))
    reps_last_session = int(state.get("reps_last_session", DEFAULT_STATE["reps_last_session"]))

    # Set initial direction based on FORWARD_TILT setting
    global FORWARD_TILT
    current_angle_target = angle_target_forward if FORWARD_TILT else angle_target_backward

    # Initialize webcam
    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("Error: Could not open webcam. Check permissions or try a different device index (e.g., 1).")
        sys.exit(1)

    # ===================================================================
    # MEDIAPIPE HAND TRACKING INITIALIZATION
    # ===================================================================
    # Configure MediaPipe Hands solution for real-time hand landmark detection
    mpHands = mp.solutions.hands
    hands = mpHands.Hands(
        static_image_mode=False,        # False = video stream mode (faster)
        max_num_hands=1,                # Track only one hand
        min_detection_confidence=0.4,   # Confidence threshold for initial detection
        min_tracking_confidence=0.25     # Confidence threshold for tracking across frames
    )
    mpDraw = mp.solutions.drawing_utils

    # Configure visual appearance of hand landmarks (smaller, subtler)
    landmark_spec = mpDraw.DrawingSpec(color=(80, 220, 100), thickness=1, circle_radius=1)
    connection_spec = mpDraw.DrawingSpec(color=(0, 180, 255), thickness=1, circle_radius=1)

    # ===================================================================
    # TRACKING VARIABLES
    # ===================================================================
    pTime = 0                          # Previous time (for FPS calculation)
    fingertip_ids = {4, 8, 12, 16, 20} # Landmark IDs for all five fingertips
    
    armed = True                       # Whether system is ready to count next rep
    reps = 0                          # Current session rep count
    
    baseline_id0 = None               # Baseline wrist position (to detect arm movement)

    show_message = False
    message_start = 0
    message_duration = 2.0  # seconds

    try:
        while True:
            # Update current target based on direction
            current_angle_target = angle_target_forward if FORWARD_TILT else angle_target_backward
            
            # ===================================================================
            # FRAME CAPTURE AND PREPROCESSING
            # ===================================================================
            success, img = cap.read()
            if not success:
                continue

            # Flip image horizontally for mirror effect (more intuitive for user)
            img = cv2.flip(img, 1)
            
            # Convert BGR to RGB (MediaPipe requires RGB input)
            imgRGB = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            
            # Process frame to detect hand landmarks
            results = hands.process(imgRGB)

            h, w, _ = img.shape

            # ===================================================================
            # DRAW TRANSPARENT VERTICAL REFERENCE LINE
            # ===================================================================
            # This helps users keep their hand centered and upright
            vertical_x = w // 2
            overlay = img.copy()
            cv2.line(overlay, (vertical_x, 0), (vertical_x, h - 1), VERT_COLOR, 2)
            # Blend the line at 10% opacity (subtle but visible)
            cv2.addWeighted(overlay, 0.1, img, 0.7, 0, img)

            # ===================================================================
            # LANDMARK DETECTION AND ANGLE CALCULATION
            # ===================================================================
            # Initialize tracking variables for this frame
            id0_xy = None    # Wrist position (landmark 0)
            id12_xy = None   # Middle finger tip (landmark 12)
            id9_xy = None    # Middle finger base (landmark 9)
            angle_deg = None    # Angle from wrist to middle fingertip
            angle_deg_2 = None  # Angle from wrist to middle finger base

            if results.multi_hand_landmarks:
                for handLms in results.multi_hand_landmarks:
                    # Draw hand skeleton with subtle styling
                    mpDraw.draw_landmarks(
                        img,
                        handLms,
                        mpHands.HAND_CONNECTIONS,
                        landmark_drawing_spec=landmark_spec,
                        connection_drawing_spec=connection_spec
                    )

                    # Extract specific landmark positions
                    for idx, lm in enumerate(handLms.landmark):
                        # Convert normalized coordinates (0-1) to pixel coordinates
                        cx, cy = int(lm.x * w), int(lm.y * h)

                        # Draw small circles on fingertips for visibility
                        if idx in fingertip_ids:
                            cv2.circle(img, (cx, cy), 2, (255, 0, 255), cv2.FILLED)

                        # Store key landmark positions
                        if idx == 0:     # Wrist
                            id0_xy = (cx, cy)
                        elif idx == 9:   # Middle finger base (MCP joint)
                            id9_xy = (cx, cy)
                        elif idx == 12:  # Middle finger tip
                            id12_xy = (cx, cy)

                    # ===================================================================
                    # CALCULATE WRIST FLEXION ANGLE (WRIST TO FINGERTIP)
                    # ===================================================================
                    # Draw line from wrist (0) to middle fingertip (12)
                    # and calculate the angle relative to vertical
                    if id0_xy is not None and id12_xy is not None:
                        # Draw thin line connecting the points
                        cv2.line(img, id0_xy, id12_xy, LINE_COLOR, 1)
                        cv2.circle(img, id0_xy, 1, LINE_COLOR, cv2.FILLED)
                        cv2.circle(img, id12_xy, 1, LINE_COLOR, cv2.FILLED)

                        # Calculate vector components
                        dx = id12_xy[0] - id0_xy[0]
                        dy = id12_xy[1] - id0_xy[1]

                        # Calculate angle from vertical (0° = straight up, 90° = horizontal)
                        # atan2(abs(dx), abs(dy)) gives angle from vertical axis
                        angle_rad = math.atan2(dx, dy)
                        angle_deg = 180 - math.degrees(angle_rad)

                    # ===================================================================
                    # CALCULATE ALIGNMENT ANGLE (WRIST TO FINGER BASE)
                    # ===================================================================
                    # This second angle helps detect if the hand is bent or twisted
                    # (not just flexed at the wrist)
                    if id0_xy is not None and id9_xy is not None:
                        cv2.line(img, id0_xy, id9_xy, LINE_COLOR, 1)
                        cv2.circle(img, id0_xy, 1, LINE_COLOR, cv2.FILLED)
                        cv2.circle(img, id9_xy, 1, LINE_COLOR, cv2.FILLED)

                        dx2 = id9_xy[0] - id0_xy[0]
                        dy2 = id9_xy[1] - id0_xy[1]

                        angle_rad_2 = math.atan2(dx2, dy2)
                        angle_deg_2 = 180 - math.degrees(angle_rad_2)

            # ===================================================================
            # DISPLAY CURRENT ANGLE
            # ===================================================================
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

            # ===================================================================
            # REP COUNTING AND VALIDATION LOGIC
            # ===================================================================
            if angle_deg is not None and angle_deg_2 is not None:
                
                # -----------------------------------------------------------
                # REP TRIGGER: Detect successful wrist flexion
                # -----------------------------------------------------------
                # Conditions:
                # 1. System is armed (not in cooldown)
                # 2. Angle exceeds target
                # 3. Hand is straight (angle_deg and angle_deg_2 are similar)
                if armed and (abs(angle_deg_2 - angle_deg) < 10) and (
                    (FORWARD_TILT and HANDEDNESS == "Right" and angle_deg < (360 - current_angle_target) and angle_deg > 180) or
                    (not FORWARD_TILT and HANDEDNESS == "Right" and angle_deg > current_angle_target and angle_deg < 180) or
                    (FORWARD_TILT and HANDEDNESS == "Left" and angle_deg > current_angle_target and angle_deg < 180) or
                    (not FORWARD_TILT and HANDEDNESS == "Left" and angle_deg < (360-current_angle_target) and angle_deg > 180)):
                    ding()
                    armed = False
                    reps += 1

                    if reps >= NUM_REPS_TO_LEVEL_UP:
                    # ---- trigger the message ----
                        show_message = True
                        message_start = time.time()
                        FORWARD_TILT = False if FORWARD_TILT else True
                        direction = "Forward" if FORWARD_TILT else "Backward"
                        new_target = angle_target_forward if FORWARD_TILT else angle_target_backward

                        # Level up logic
                        save_session(USER_ID, int(angle_target_forward), int(angle_target_backward), reps, level_up=True)

                        if FORWARD_TILT:
                            angle_target_forward += ANGLE_INCREMENT
                        else:
                            angle_target_backward += ANGLE_INCREMENT

                        reps = 0

                        

                    # Display "DING!" text briefly
                    cv2.putText(img, "DING!", (w // 2 - 70, 120),
                                cv2.FONT_HERSHEY_PLAIN, 3, (0, 200, 255), 3)

                # -----------------------------------------------------------
                # HAND ALIGNMENT CHECK
                # -----------------------------------------------------------
                # If the two angles differ significantly, the hand is bent/twisted
                # This prevents cheating by curling fingers instead of flexing wrist
                if (abs(angle_deg_2 - angle_deg) > 20 and abs(angle_deg_2 - angle_deg) < 300):
                    warn_text = "Keep your hand straight."
                    x_text = max(10, w // 2 - 150)
                    cv2.putText(img, warn_text, (x_text, 80),
                                cv2.FONT_HERSHEY_PLAIN, 1.5, (0, 0, 255), 2)

                # -----------------------------------------------------------
                # RE-ARM SYSTEM
                # -----------------------------------------------------------
                # Once the wrist returns to near-zero angle, allow next rep
                if (not armed) and (angle_deg <= RESET_THRESHOLD or angle_deg >= (360 - RESET_THRESHOLD)):
                    armed = True
                    # Update baseline wrist position for drift detection
                    if id0_xy is not None:
                        baseline_id0 = id0_xy

                # -----------------------------------------------------------
                # WRIST DRIFT DETECTION
                # -----------------------------------------------------------
                # Ensure user is only moving wrist, not the entire arm
                if (id0_xy is not None and id12_xy is not None):
                    # Set initial baseline on first detection
                    if baseline_id0 is None:
                        baseline_id0 = id0_xy

                    # Calculate current hand length (wrist to fingertip distance)
                    hand_len = math.hypot(id12_xy[0] - id0_xy[0], id12_xy[1] - id0_xy[1])

                    if hand_len > 0:
                        # Calculate how far wrist has moved from baseline
                        wrist_drift = math.hypot(id0_xy[0] - baseline_id0[0], 
                                                 id0_xy[1] - baseline_id0[1])
                        
                        # If wrist moved more than 1/3 of hand length, warn user
                        if wrist_drift > (hand_len / 3.0):
                            armed = False  # Disarm to prevent counting bad reps
                            warn_text = "Try not to move your arm, just your wrist."
                            x_text = max(10, w // 2 - 320)
                            cv2.putText(img, warn_text, (x_text, 50),
                                        cv2.FONT_HERSHEY_PLAIN, 1.5, (0, 0, 255), 2)

            # ===================================================================
            # HEADS-UP DISPLAY (HUD)
            # ===================================================================
            # Show both target angles
            tilt = "Forward" if FORWARD_TILT else "Backward"
            cv2.putText(img, f"Target ({tilt}): {int(current_angle_target)} deg  [F:{int(angle_target_forward)}° B:{int(angle_target_backward)}°]", 
                       (10, 160), cv2.FONT_HERSHEY_PLAIN, 1.7, HUD_COLOR, 2)
            
            # Show current reps with last session's count as reference
            if reps_last_session > 0:
                cv2.putText(img, f"Reps: {reps} (Last: {reps_last_session})", (10, 200),
                            cv2.FONT_HERSHEY_PLAIN, 2, HUD_COLOR, 2)
            else:
                cv2.putText(img, f"Reps: {reps}", (10, 200),
                            cv2.FONT_HERSHEY_PLAIN, 2, HUD_COLOR, 2)

            # Show controls hint
            cv2.putText(img, "'q' quit | 'l' level up | 'b' toggle direction     Hand: " + HANDEDNESS, 
                       (10, h - 20), cv2.FONT_HERSHEY_PLAIN, 1, HUD_COLOR, 1)

            # ===================================================================
            # DISPLAY AND INPUT HANDLING
            # ===================================================================
            
            # Start with the normal frame
            frame_to_show = img.copy()

            # Overlay the message for the duration
            if show_message:
                if time.time() - message_start < message_duration:
                    cv2.putText(
                        frame_to_show,
                        f"Level Up! New {direction} target: {int(new_target)} deg",
                        (w // 2, h // 2),
                        cv2.FONT_HERSHEY_PLAIN,
                        2,
                        (0, 255, 0),
                        2
                    )
                else:
                    show_message = False  # stop showing after 2 seconds

            # Only ONE imshow per frame for that window
            cv2.imshow("Image", frame_to_show)
            key = cv2.waitKey(1) & 0xFF
            
            # Quit on 'q' key
            if key == ord('q'):
                break
            
            # Level up on 'l' key (increase target angle)
            elif key == ord('l'):
                # Save current session before leveling up
                save_session(USER_ID, int(angle_target_forward), int(angle_target_backward), reps, level_up=False)
                
                # Increase angle target for current direction
                if FORWARD_TILT:
                    if angle_target_forward + ANGLE_INCREMENT <= MAX_ANGLE_TARGET_FORWARD:
                        angle_target_forward += ANGLE_INCREMENT
                    else:
                        angle_target_forward = MIN_ANGLE_TARGET_FORWARD  # Wrap around if at max
                else:
                    if angle_target_backward + ANGLE_INCREMENT <= MAX_ANGLE_TARGET_BACKWARD:
                        angle_target_backward += ANGLE_INCREMENT
                    else:
                        angle_target_backward = MIN_ANGLE_TARGET_BACKWARD  # Wrap around if at max
                
                # Reset for new level
                reps_last_session = reps
                reps = 0
                
                # Show level up message
                temp_img = img.copy()
                direction = "Forward" if FORWARD_TILT else "Backward"
                new_target = angle_target_forward if FORWARD_TILT else angle_target_backward
                cv2.putText(temp_img, f"Level Up! New {direction} target: {int(new_target)} deg",
                            (w // 2 - 350, h // 2),
                            cv2.FONT_HERSHEY_PLAIN, 3, (0, 255, 0), 3)
                cv2.imshow("Image", temp_img)
                cv2.waitKey(1500)  # Show message for 1.5 seconds
            
            # Toggle direction on 'b' key
            elif key == ord('b'):
                # Save current progress before switching
                save_session(USER_ID, int(angle_target_forward), int(angle_target_backward), reps, level_up=False)
                
                # Toggle direction
                FORWARD_TILT = not FORWARD_TILT
                
                # Reset reps for new direction
                reps_last_session = reps
                reps = 0
                
                # Show direction change message
                temp_img = img.copy()
                direction = "Forward" if FORWARD_TILT else "Backward"
                new_target = angle_target_forward if FORWARD_TILT else angle_target_backward
                cv2.putText(temp_img, f"Direction: {direction} | Target: {int(new_target)} deg",
                            (w // 2 - 300, h // 2),
                            cv2.FONT_HERSHEY_PLAIN, 3, (255, 165, 0), 3)
                cv2.imshow("Image", temp_img)
                cv2.waitKey(1000)  # Show message for 1 second
            
            # Check if window was closed
            if cv2.getWindowProperty("Image", cv2.WND_PROP_VISIBLE) < 1:
                break

    finally:
        # ===================================================================
        # CLEANUP AND SESSION SAVE
        # ===================================================================
        # Save the completed session to Supabase before exiting
        print(f"\nSession complete: {reps} reps at Forward:{int(angle_target_forward)}° Backward:{int(angle_target_backward)}°")
        save_session(USER_ID, int(angle_target_forward), int(angle_target_backward), reps, level_up=False)

if __name__ == "__main__":
    main()