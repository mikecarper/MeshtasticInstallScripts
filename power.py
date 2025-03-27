#!/usr/bin/env python3

import time
import board
import busio
from adafruit_ina219 import ADCResolution, BusVoltageRange, INA219
import sys
import os
import glob
import psutil

# ----- Battery Parameters -----
battery_capacity_wh = 400.0    # Total battery capacity in watt-hours
battery_full_voltage  = 14.0   # Voltage considered as full (100% SOC)
battery_empty_voltage = 10.5   # Voltage considered as empty (0% SOC)

# ----- Initialize I2C Bus and INA219 Sensor -----
try:
    i2c = busio.I2C(board.SCL, board.SDA)
    ina = INA219(i2c)
except ValueError as e:
    # Check if the message indicates hardware I2C is not enabled
    if "No Hardware I2C on" in str(e):
        print("I²C appears to be disabled. Please run:")
        print("   sudo raspi-config")
        print("   Go to 'Interface Options' → 'I2C' → select 'Enable'.")
        sys.exit(1)
    else:
        # Some other ValueError
        raise

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

# ----- INA219 Optional Configuration -----
ina.bus_adc_resolution = ADCResolution.ADCRES_12BIT_32S
ina.shunt_adc_resolution = ADCResolution.ADCRES_12BIT_32S
ina.bus_voltage_range = BusVoltageRange.RANGE_16V


# ----- Thermal Sensor Setup -----
# Find all thermal zones (typically /sys/class/thermal/thermal_zone*)
thermal_sensors = glob.glob("/sys/class/thermal/thermal_zone*")
thermal_count = len(thermal_sensors)
min_thermal = [float('inf')] * thermal_count
max_thermal = [float('-inf')] * thermal_count

# Initialize CPU tracking for each logical core
cpu_count = psutil.cpu_count(logical=True)
min_cpu = [100.0] * cpu_count  # CPU usage is a percentage (0 to 100)
max_cpu = [0.0] * cpu_count


def get_thermal_readings():
    """Return a list of formatted strings for each thermal sensor reading."""
    readings = []
    for sensor in thermal_sensors:
        try:
            with open(f"{sensor}/temp", "r") as f:
                temp_mdeg = int(f.read().strip())
                temp_c = temp_mdeg / 1000.0
            with open(f"{sensor}/type", "r") as f:
                sensor_type = f.read().strip()
        except Exception:
            sensor_type = "Unknown"
            temp_c = None
        if temp_c is not None:
            readings.append(f"{os.path.basename(sensor)} ({sensor_type}): {temp_c:.2f}°C")
    return readings

# ----- Reserve Display Area -----
# Battery info will occupy 5 lines.
# Thermal sensor info will occupy one line per sensor.
total_lines = 5 + thermal_count + cpu_count


# Print initial header placeholders.
print(total_lines)
print("Config register:")
print("  bus_voltage_range:    0x%1X" % ina.bus_voltage_range)
print("  gain:                 0x%1X" % ina.gain)
print("  bus_adc_resolution:   0x%1X" % ina.bus_adc_resolution)
print("  shunt_adc_resolution: 0x%1X" % ina.shunt_adc_resolution)
print("  mode:                 0x%1X" % ina.mode)
print("         MIN      NOW      MAX\033[K")

battery_full = False
#sys.exit()
while True:
    try:
        # ----- Update Time and Compute dt -----
        current_time = time.monotonic()
        dt = current_time - last_time
        last_time = current_time

        # ----- Read Battery Sensor Values -----
        voltage = ina.bus_voltage          # in volts
        shunt_voltage = ina.shunt_voltage    # in volts
        current_val = ina.current            # in milliamps
        power = ina.power                    # in watts

        # Update min/max battery values.
        min_voltage = min(min_voltage, voltage)
        max_voltage = max(max_voltage, voltage)
        min_current = min(min_current, current_val)
        max_current = max(max_current, current_val)
        min_power = min(min_power, power)
        max_power = max(max_power, power)

        # ----- Energy Integration (Wh) -----
        if current_val < 0:
            energy_wh += -(voltage * current_val) / 1000 * (dt / 3600.0)
        min_energy_wh = min(min_energy_wh, energy_wh)
        max_energy_wh = max(max_energy_wh, energy_wh)

        # ----- Calculate Battery SOC -----
        if voltage >= battery_full_voltage:
            battery_full = True

        if not battery_full:
            battery_percentage = (voltage - battery_empty_voltage) / (battery_full_voltage - battery_empty_voltage) * 100
            battery_percentage = max(0, min(battery_percentage, 100))
            soc_str = "{:7.2f}%?".format(battery_percentage)
        else:
            battery_percentage = max(0, 100 - (energy_wh / battery_capacity_wh * 100))
            soc_str = "{:7.2f}%".format(battery_percentage)


        # ----- Update Display -----
        if not first_iteration:
            sys.stdout.write(f"\033[{total_lines}F")
        else:
            first_iteration = False

        # Battery sensor block (min, now, max)
        print(" V:  {:7.2f}  {:7.2f}  {:7.2f}\033[K".format(min_voltage, voltage, max_voltage))
        print("mA:  {:7.2f}  {:7.2f}  {:7.2f}\033[K".format(min_current, current_val, max_current))
        print(" W:  {:7.2f}  {:7.2f}  {:7.2f}\033[K".format(min_power, power, max_power))
        print("Wh:  {:7.4f}  {:7.4f}  {:7.4f}\033[K".format(min_energy_wh, energy_wh, max_energy_wh))

        # CPU usage: update and print min, current, and max for each core.
        per_cpu_usage = psutil.cpu_percent(interval=0, percpu=True)
        for i, usage in enumerate(per_cpu_usage):
            min_cpu[i] = min(min_cpu[i], usage)
            max_cpu[i] = max(max_cpu[i], usage)
            print(f"CPU {i}: {min_cpu[i]:5.1f}   {usage:5.1f}    {max_cpu[i]:5.1f}%\033[K")
            
        # ----- Read Thermal Sensors -----
        # Assume get_thermal_readings returns a list of float temperatures.
        thermal_readings = get_thermal_readings()
        for i, reading in enumerate(thermal_readings):
            # Assume the reading is formatted as: "thermal_zone0 (cpu-thermal): 39.70°C"
            # Split on ":" and get the numeric part
            numeric_part = reading.split(":")[-1].replace("°C", "").strip()
            reading_val = float(numeric_part)
            
            min_thermal[i] = min(min_thermal[i], reading_val)
            max_thermal[i] = max(max_thermal[i], reading_val)
            print("Temp{}: {:6.2f}  {:6.2f}   {:6.2f}\033[K".format(i, min_thermal[i], reading_val, max_thermal[i]))

        # Pad with blank lines if needed.
        for _ in range(thermal_count - len(thermal_readings)):
            print(" " + "\033[K")

        print("SOC: {}".format(soc_str) + "\033[K")

        sys.stdout.flush()
        time.sleep(0.1)

    except OSError as e:
        # On I/O error, move cursor to the bottom line and print the error message on that same line.
        sys.stdout.write("\033[1F")
        sys.stdout.write("\rEncountered an error: {}. Waiting 10 seconds and trying again.\033[K".format(e))
        sys.stdout.flush()
        time.sleep(10)
        continue
