#Grip script
from supabase import create_client, Client
from dotenv import load_dotenv
import os
import serial
import time
import sys

# Configure the serial port
ser = serial.Serial('COM3', 9600, timeout=1)
UUID = "" #Somehow imported later
session_id = "" #Get UUID, find most recent session_id, +1
# Initialize Supabase
load_dotenv()
supabase: Client = create_client(os.getenv("SUPABASE_URL"), os.getenv("SUPABASE_KEY"))

time_window = 10  # Time window in seconds, the user should be made aware of this in frontend
start_time = time.time()
grip_vals = []

try:
    while time.time() - start_time < time_window:
        if ser.in_waiting > 0:
            line = ser.readline().decode('utf-8').strip()  # Read, decode, and remove whitespace
            print(f"Received from Arduino: {line}")

            # Example: Parsing data if sent as "SensorValue:123"
            if "SensorValue:" in line:
                try:
                    value_str = line.split(":")[1]
                    sensor_value = int(value_str)
                    grip_vals.append(sensor_value)
                    print(f"Parsed sensor value: {sensor_value}")
                except (ValueError, IndexError):
                    print("Error parsing data.")

        time.sleep(0.1)  # Small delay to prevent busy-waiting

except KeyboardInterrupt:
    print("Exiting program.")

finally:
    ser.close()  # Close the serial port when done
max_val = 0
if len(grip_vals) == 0:
    print("No data received from Arduino.")
    sys.exit(1)
for val in grip_vals:
    if val > max_val:
        max_val = val
baseline_data = supabase.table("baseline").select("base_grip").eq("UUID", UUID).execute()
baseline_value = float(baseline_data[0]["base_grip"])
ratio = max_val / baseline_value

supabase.table("grip").insert({
    "UUID": UUID,
    "session_id": session_id,
    "fsr_palm": max_val,
    "r_fsr_palm": ratio
}).execute()
#This is in accordance with Box. It seems that the actual supabase table may have more columns.
