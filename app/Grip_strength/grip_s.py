#Grip script
import serial
import time

# Configure the serial port
ser = serial.Serial('COM3', 9600, timeout=1)

#Replace once baseline exists
base_GT = float

time_window = 10  # Time window in seconds
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

    print(f"Maximum grip value recorded: {max_val}")

finally:
    if base_GT is None:
        print("There are no baseline values.")
    else:
        r_GT = max_val / base_GT #Float

    #print session results
    print("\nGrip session result:")
    print("Max grip value:", max_val)
    print("Ratio to baseline grip strength:", r_GT)

ser.close()  # Close the serial port when done
