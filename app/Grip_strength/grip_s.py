#Grip script
from supabase import create_client, Client
import serial
import time

# Configure the serial port
ser = serial.Serial('COM3', 9600, timeout=1)
UUID = "" #Somehow imported later
session_id = "" #Get UUID, find most recent session_id, +1
# Initialize Supabase
supabase_url: str = "https://cmmumwwzydfebahhgfyi.supabase.co"
supabase_key: str = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNtbXVtd3d6eWRmZWJhaGhnZnlpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI4MDkwNTAsImV4cCI6MjA3ODM4NTA1MH0.zJBi0owKoaycNzmtAm9_5ZsUwXIUmxAGuCy0AhsaoZc"
supabase: Client = create_client(supabase_url, supabase_key)

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

    max_val = 0
    for val in grip_vals:
        if val > max_val:
            max_val = val
finally:
    ser.close()  # Close the serial port when done
#print(f"Maximum grip value recorded: {max_val}")
#Todo: Read from supabase to determine ratio to baseline
#Todo: Determine APIresponse format to extract the value as float
baseline = supabase.table("baseline").select("base_grip").eq("UUID", UUID).execute()
print(baseline)
#ratio = max_val / baseline
#Todo: Send to supabase the recorded maximum and the determined ratio (+UUID and session_id?)

