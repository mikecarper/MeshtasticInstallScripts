## Enable INA219 0x40 (64) and measure it
```
meshtastic --set power.device_battery_ina_address 64
meshtastic --set telemetry.power_measurement_enabled true
meshtastic --debug --listen 2>&1 | grep 'ch3_voltage'
```

## Build via linux cli Init
```
sudo apt -y install git python3-pip pipx
pipx install platformio
pipx ensurepath

export PATH="$HOME/.local/bin:$PATH"

git clone https://github.com/meshtastic/firmware.git
cd firmware && git submodule update --init
```

## add in extra file to the meshtastic firmware
```
git clone https://github.com/mikecarper/MeshtasticInstallScripts

cd MeshtasticInstallScripts/
git pull

chmod +x enableGPOIfirmware.sh

cp enableGPOIfirmware.sh ~/firmware/
cp extra.patch ~/firmware/
```

## Build via linux cli Compile
```
# Get latest changes
git reset --hard
git pull --recurse-submodules

# Set DMESHTASTIC_EXCLUDE_REMOTEHARDWARE=0
./enableGPOIfirmware.sh

# apply other changes
git apply extra.patch

# Compile Firmware
pio run -e station-g2

# Copy Firmware
cp ~/firmware/.pio/build/station-g2/firmware.factory.bin

```

