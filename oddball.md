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

# Copy Firmware to the remote server
scp ~/firmware/.pio/build/station-g2/firmware.factory.bin bbs@100.100.100.100:"~/meshfirmware/meshtastic_firmware/compiled"


```


## Auto reboot at 3:30am
```

if ! sudo crontab -l 2>/dev/null | grep -Fq "30 3 * * * /sbin/shutdown -r now"; then
    (sudo crontab -l 2>/dev/null; echo "30 3 * * * /sbin/shutdown -r now") | sudo crontab -
fi
```
