#!/usr/bin/env python3

# chmod +x power.py
# ./power.py -low   Turn off high power mode. As long as the script is running it will be set in low power mode.
# ./power.py        Powercycle the Station G2

import RPi.GPIO as GPIO
import time
import argparse

# Parse command-line arguments.
parser = argparse.ArgumentParser(description="Control relays on a Raspberry Pi.")
parser.add_argument('--low', action='store_true', help='Only control relay_pin_a')
args = parser.parse_args()

# Use Broadcom (BCM) pin numbering.
GPIO.setmode(GPIO.BCM)

# Define relay pins.
relay_pin_a = 17  # Physical pin 11
relay_pin_b = 27  # Physical pin 13

# Setup the relay control pins as outputs.
GPIO.setup(relay_pin_a, GPIO.OUT)
GPIO.setup(relay_pin_b, GPIO.OUT)

try:
    if args.low:
        # Control only relay_pin_a.
        GPIO.output(relay_pin_a, GPIO.LOW)  # Turn on relay A (active low)
        print("Relay ON: pin 17/11")
        print("Station G2 in low power mode")
        while True:
            time.sleep(5)
    else:
        # Control both relay channels simultaneously.
        GPIO.output(relay_pin_a, GPIO.LOW)
        GPIO.output(relay_pin_b, GPIO.LOW)
        print("Relay ON: pin 17/11 & 27/13")
        print("Powercycling Station G2")
        time.sleep(3)
        GPIO.output(relay_pin_a, GPIO.HIGH)
        GPIO.output(relay_pin_b, GPIO.HIGH)
        print("Relay OFF: pin 17/11 & 27/13")
except KeyboardInterrupt:
    print("Exiting...")
finally:
    GPIO.cleanup()
