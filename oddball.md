## Enable INA219 0x40 (64) and measure it
```
meshtastic --set power.device_battery_ina_address 64
meshtastic --set telemetry.power_measurement_enabled true
meshtastic --debug --listen 2>&1 | grep 'ch3_voltage'
```

## Build via linux cli
```
sudo apt -y install git  python3-pip pipx
sudo apt install pipx
export PATH="$HOME/.local/bin:$PATH"

git clone https://github.com/meshtastic/firmware.git
cd firmware && git submodule update --init
git pull --recurse-submodules


```

