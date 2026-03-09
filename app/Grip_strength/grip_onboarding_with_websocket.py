"""
Grip Strength Test with WebSocket Streaming
===========================================

Measures grip strength over a 10 second window and streams real-time
sensor values to a Flutter app.

Process:
1. User squeezes grip device for 10 seconds
2. Arduino sends FSR sensor values
3. Values streamed to Flutter via WebSocket
4. Top 60% averaged to determine max grip strength
5. Saved to Supabase
"""

import asyncio
import websockets
import threading
import json
import serial
import time
import numpy as np
import os
from dotenv import load_dotenv
from supabase import create_client, Client
from datetime import datetime
import random

# =========================================================
# CONFIG
# =========================================================

load_dotenv()

SERIAL_PORT = "COM3"
BAUD_RATE = 9600
TIME_WINDOW = 10

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# =========================================================
# GLOBAL STATE (STREAMED TO FLUTTER)
# =========================================================

grip_state = {
    "phase": "instructions",
    "current_value": 0,
    "elapsed_time": 0,
    "time_limit": TIME_WINDOW,
    "values": [],
    "max_grip": None,
    "ratio": None,
    "message": "Press start to begin grip test"
}

quit_requested = False


# =========================================================
# WEBSOCKET SERVER
# =========================================================

async def handle_websocket(websocket, path):
    print("✓ Flutter connected")

    try:
        while not quit_requested:
            await websocket.send(json.dumps(grip_state))

            try:
                await asyncio.wait_for(websocket.recv(), timeout=0.01)
            except asyncio.TimeoutError:
                pass
            except websockets.exceptions.ConnectionClosed:
                break

            await asyncio.sleep(0.033)

    except websockets.exceptions.ConnectionClosed:
        print("✗ Flutter disconnected")


async def start_websocket_server():
    server = await websockets.serve(handle_websocket, "localhost", 8765)
    print("✓ WebSocket server started: ws://localhost:8765")
    await server.wait_closed()


# =========================================================
# SERIAL SETUP
# =========================================================

def init_serial():
    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=1)
        print("✓ Arduino connected")
        return ser
    except:
        print("⚠ Arduino not detected. Using simulation mode.")
        return None


# =========================================================
# GRIP TEST
# =========================================================

def run_grip_test():

    global grip_state

    ser = init_serial()

    start_time = time.time()
    grip_vals = []

    grip_state["phase"] = "testing"
    grip_state["message"] = "Squeeze as hard as you can!"

    while time.time() - start_time < TIME_WINDOW:

        elapsed = time.time() - start_time
        grip_state["elapsed_time"] = elapsed

        value = None

        if ser and ser.in_waiting > 0:

            line = ser.readline().decode().strip()

            if "SensorValue:" in line:
                try:
                    value = int(line.split(":")[1])
                except:
                    pass

        # simulation fallback
        if value is None:
            value = random.randint(20, 100)

        grip_vals.append(value)

        grip_state["current_value"] = value
        grip_state["values"] = grip_vals[-50:]

        time.sleep(0.05)

    if ser:
        ser.close()

    # =========================================================
    # PROCESS RESULTS
    # =========================================================

    if len(grip_vals) == 0:
        print("No data received.")
        return

    sorted_vals = np.sort(grip_vals)[::-1]
    len60 = int(0.6 * len(sorted_vals))

    top_vals = sorted_vals[:len60]
    max_val = float(np.mean(top_vals))

    print("Max Grip:", max_val)

    # =========================================================
    # BASELINE + RATIO
    # =========================================================

    user = supabase.auth.get_user()
    UUID = user.user.id

    baseline_data = supabase.table("baseline").select("base_grip").eq("UUID", UUID).execute()

    baseline_value = float(baseline_data.data[0]["base_grip"])

    ratio = max_val / baseline_value

    # =========================================================
    # SAVE TO SUPABASE
    # =========================================================

    supabase.table("grip").insert({

        "user_id": UUID,
        "session_id": 1,
        "fsr_palm": max_val,
        "r_fsr_palm": ratio,
        "created_at": datetime.utcnow().isoformat()

    }).execute()

    print("✓ Saved to Supabase")

    # =========================================================
    # UPDATE STATE FOR FLUTTER
    # =========================================================

    grip_state.update({
        "phase": "complete",
        "max_grip": max_val,
        "ratio": ratio,
        "message": "Grip test complete!"
    })


# =========================================================
# MAIN
# =========================================================

def main():

    global quit_requested

    # start websocket server
    def run_ws():
        asyncio.set_event_loop(asyncio.new_event_loop())
        asyncio.get_event_loop().run_until_complete(start_websocket_server())

    threading.Thread(target=run_ws, daemon=True).start()

    time.sleep(0.5)

    input("Press ENTER to start grip test")

    run_grip_test()

    input("Press ENTER to exit")

    quit_requested = True


if __name__ == "__main__":
    main()