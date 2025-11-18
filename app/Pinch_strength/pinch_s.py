import serial
import time

# Configure the serial port
ser = serial.Serial('COM3', 9600, timeout=0.1)

# replace these once baseline calibration exists
base_IT = None
base_MT = None

# time values in seconds
time_window = 10
start = time.time()
# empty arrays for index and middle figer values
ind_vals = []
mid_vals = []

try:
    while time.time() - start < time_window:
        if ser.in_waiting > 0:
            line = ser.readline().decode().strip()
            print("Received:", line)

            try:
                parts = line.split(',')
                data = {}
                
                for piece in parts:
                    split_piece = piece.split(':')
                    
                    if len(split_piece) == 2:
                        key = split_piece[0].strip()
                        value = float(split_piece[1].strip())
                        data[key] = value

                if 'index' in data:
                    ind_vals.append(data['index'])
                if 'middle' in data:
                    mid_vals.append(data['middle'])
                    
            except:
                print("Skipping invalid packet.")

        time.sleep(0.1) # small delay between sensor reads
except KeyboardInterrupt:
    print("Exiting.")
finally:
    if base_IT is None or base_MT is None:
        print("There are no baseline values.")
    else:
        if len(ind_vals) > 0:
            I_T = min(ind_vals)
        else:
            I_T = 0

        if len(mid_vals) > 0:
            M_T = min(mid_vals)
        else:
            M_T = 0

        if base_IT:
            r_IT = I_T / base_IT
        else:
            r_IT = 0

        if base_MT:
            r_MT = M_T / base_MT
        else:
            r_MT = 0

        # prints results for session
        print("\nPinch session result:")
        print("Index-Thumb(IT):", I_T)
        print("Middle-Thumb(MT):", M_T)
        print("Ratio of Index-Thumb(r_IT):", round(r_IT, 3))
        print("Ratio of Middle-Thumb(r_MT):", round(r_MT, 3))

    ser.close() # closes serial port when finished 
