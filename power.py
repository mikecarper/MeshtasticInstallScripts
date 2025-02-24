#!/usr/bin/env python3

import time
import board
import busio
from adafruit_ina219 import ADCResolution, BusVoltageRange, INA219
import sys

# ----- Battery Parameters -----
battery_capacity_wh = 400.0    # Total battery capacity in watt-hours (adjust as needed)
battery_full_voltage  = 14.0   # Voltage considered as full (100% SOC)
battery_empty_voltage = 10.5   # Voltage considered as empty (0% SOC)

# ----- Initialize I2C Bus and Sensor -----
i2c = busio.I2C(board.SCL, board.SDA)
ina = INA219(i2c)

# ----- Initialize Min/Max Variables -----
min_voltage = float('inf')
max_voltage = -float('inf')
min_shunt_voltage = float('inf')
max_shunt_voltage = -float('inf')
min_current = float('inf')
max_current = -float('inf')
min_power   = float('inf')
max_power   = -float('inf')
min_energy_wh = float('inf')
max_energy_wh = -float('inf')
energy_wh = 0.0

# Use time.monotonic() for accurate dt measurement
last_time = time.monotonic()

first_iteration = True

# optional : change configuration to use 32 samples averaging for both bus voltage and shunt voltage
ina.bus_adc_resolution = ADCResolution.ADCRES_12BIT_32S
ina.shunt_adc_resolution = ADCResolution.ADCRES_12BIT_32S
# optional : change voltage range to 16V
ina.bus_voltage_range = BusVoltageRange.RANGE_16V

print("Config register:")
print("  bus_voltage_range:    0x%1X" % ina.bus_voltage_range)
print("  gain:                 0x%1X" % ina.gain)
print("  bus_adc_resolution:   0x%1X" % ina.bus_adc_resolution)
print("  shunt_adc_resolution: 0x%1X" % ina.shunt_adc_resolution)
print("  mode:                 0x%1X" % ina.mode)
print("")


# Print header once
print("         MIN      NOW      MAX\033[K")

battery_full = False
while True:
    try:
        # Calculate time elapsed since last loop (in seconds)
        current_time = time.monotonic()
        dt = current_time - last_time
        last_time = current_time

        # ----- Read Sensor Values -----
        voltage = ina.bus_voltage    # in volts
        shunt_voltage = ina.shunt_voltage
        current = ina.current        # in milliamps
        power   = ina.power          # in watts

        # Update min/max values
        min_voltage = min(min_voltage, voltage)
        max_voltage = max(max_voltage, voltage)
        
        min_shunt_voltage = min(min_shunt_voltage, shunt_voltage)
        max_shunt_voltage = max(max_shunt_voltage, shunt_voltage)
        
        min_current = min(min_current, current)
        max_current = max(max_current, current)
        
        min_power   = min(min_power, power)
        max_power   = max(max_power, power)

        # ----- Energy Integration (Wh) -----
        # Assume discharging current is negative.
        if current < 0:
            # Compute incremental energy (Wh): (voltage * |current| / 1000) * (dt in hours)
            energy_wh += -(voltage * current) / 1000 * (dt / 3600.0)
        min_energy_wh = min(min_energy_wh, energy_wh)
        max_energy_wh = max(max_energy_wh, energy_wh)

        # ----- Calculate Battery Percentage (SOC) -----
        # If voltage is below battery_full_voltage, guess SOC using linear interpolation.
        # Append a '?' to indicate it's a guess.
        if voltage >= battery_full_voltage:
            battery_full = True
            
        if not battery_full:
            battery_percentage = (voltage - battery_empty_voltage) / (battery_full_voltage - battery_empty_voltage) * 100
            battery_percentage = max(0, min(battery_percentage, 100))
            soc_str = "{:7.2f}%?".format(battery_percentage)
        else:
            # When full voltage is hit, use energy integration method.
            battery_percentage = max(0, 100 - (energy_wh / battery_capacity_wh * 100))
            soc_str = "{:7.2f}%".format(battery_percentage)

        # ----- Update Display -----
        # Overwrite previous output (5 lines: 4 measurement rows + 1 SOC row)
        if not first_iteration:
            sys.stdout.write("\033[5F")
        else:
            first_iteration = False

        # Print a compact matrix of MIN, NOW, and MAX values plus SOC:
        print(" V:  {:7.2f}  {:7.2f}  {:7.2f}\033[K".format(min_voltage, voltage, max_voltage))
        #print(" V:  {:7.2f}  {:7.2f}  {:7.2f}\033[K".format(min_shunt_voltage, shunt_voltage, max_shunt_voltage))
        print("mA:  {:7.2f}  {:7.2f}  {:7.2f}\033[K".format(min_current, current, max_current))
        print(" W:  {:7.2f}  {:7.2f}  {:7.2f}\033[K".format(min_power, power, max_power))
        print("Wh:  {:7.4f}  {:7.4f}  {:7.4f}\033[K".format(min_energy_wh, energy_wh, max_energy_wh))
        print("SOC: {}".format(soc_str) + "\033[K")

        sys.stdout.flush()
        time.sleep(0.1)
    
    except OSError as e:
        sys.stdout.write("\033[1F")
        print(f"Encountered an error: {e}. Waiting 10 seconds and trying again.\033[K")
        time.sleep(10)
        continue
