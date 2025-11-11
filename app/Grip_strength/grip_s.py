// Grip script
import serial
import time

# Configure the serial port
ser = serial.Serial('COM3', 9600, timeout=1) 

try:
    while True:
        if ser.in_waiting > 0:
            line = ser.readline().decode('utf-8').strip() # Read, decode, and remove whitespace
            print(f"Received from Arduino: {line}")

            # Example: Parsing data if sent as "SensorValue:123"
            if "SensorValue:" in line:
                try:
                    value_str = line.split(":")[1]
                    sensor_value = int(value_str)
                    print(f"Parsed sensor value: {sensor_value}")
                except (ValueError, IndexError):
                    print("Error parsing data.")

        time.sleep(0.1) # Small delay to prevent busy-waiting

except KeyboardInterrupt:
    print("Exiting program.")
finally:
    ser.close() # Close the serial port when done
