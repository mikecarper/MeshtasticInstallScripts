## Enable INA219 0x40 (64) and measure it
```
meshtastic --set power.device_battery_ina_address 64
meshtastic --set telemetry.power_measurement_enabled true
meshtastic --debug --listen 2>&1 | grep 'ch3_voltage'
```

