#import serial
import time
import random


# Configure the serial port
#ser = serial.Serial('COM3', 9600, timeout=0.1)

# replace these once baseline calibration exists
base_IT = None
base_MT = None

# time values in seconds
time_window = 10
start = time.time()
# empty arrays for index and middle finger values 
ind_vals = []
mid_vals = []

# code is using dummy data
USE_DUMMY = True
dummy_stream = dummy_data()

try:
    while time.time() - start < time_window:
        if ser.in_waiting > 0:
            # test code for dummy data
            if USE_DUMMY:
                line = next(dummy_stream)
            else:
             line = ser.readline().decode().strip()   
            #line = ser.readline().decode().strip()
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
    # Calculates the maximum pinch strength
    I_T = max(ind_vals) if len(ind_vals) > 0 else 0
    M_T = max(mid_vals) if len(mid_vals) > 0 else 0

    print("\nMaximum Pinch Strength Result:")
    print("Index-Thumb(IT):", I_T)
    print("Middle-Thumb(MT):", M_T)

    # computes ratios given that the baselines exist
    if base_IT not in (None, 0):
        r_IT = I_T / base_IT
        print("Ratio of Index-Thumb(r_IT):", round(r_IT, 3))
    else:
        print("There aer no baseline values for the Index-Thumb ratio.")

    if base_MT not in (None, 0):
        r_MT = M_T / base_MT
        print("Ratio of Middle-Thumb(r_MT):", round(r_MT, 3))
    else:
        print("There are no baseline values for the Middle-Thumb ratio.")

    
        # prints results for maximum pinch strength session
        print("\n Maximum Pinch Strength Result:")
        print("Index-Thumb(IT):", I_T)
        print("Middle-Thumb(MT):", M_T)
        print("Ratio of Index-Thumb(r_IT):", round(r_IT, 3))
        print("Ratio of Middle-Thumb(r_MT):", round(r_MT, 3))

    ser.close() # closes serial port when finished 
