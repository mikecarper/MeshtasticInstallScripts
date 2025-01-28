Get 64 bit desktop and enable SSH & WiFi from the imager  

# Base pi config
```
sudo raspi-config
```  

system options -> boot/auto login -> console autologin  

```
wget https://raw.githubusercontent.com/mikecarper/MeshtasticInstallScripts/refs/heads/main/InstallFiles.sh
chmod +x InstallFiles.sh
./InstallFiles.sh
```

```
sudo apt update
sudo apt -y upgrade
sudo apt -y install git jq ntp virtualenvwrapper pipx fonts-noto-color-emoji npm software-properties-common mosquitto mosquitto-clients
sudo hostnamectl set-hostname GeoPlace
```


# Install VPN
100 devices on the free tier  
https://login.tailscale.com/admin/  
```
curl -fsSL https://tailscale.com/install.sh | sh  
curl -fsSL https://tailscale.com/install.sh | sh  
sudo tailscale up  
```


# Setup multiple wifi connections
 ```
sudo nmcli dev wifi list
sudo nmcli dev wifi connect "John Doe’s iPhone" password "setec astronomy"
```
Verify the saved SSID
```
sudo nmcli connection show
```





# Install firmware update tools
https://meshtastic.org/docs/getting-started/flashing-firmware/esp32/cli-script/  
```
cd ~
python3 -m venv meshtastic-venv
source meshtastic-venv/bin/activate
pip install --upgrade esptool 
esptool.py chip_id
```


# Select the firmware for the g2
```
cd ~
wget https://raw.githubusercontent.com/mikecarper/MeshtasticInstallScripts/refs/heads/main/firmware-selection-g2.sh
chmod +x firmware-selection-g2.sh
./firmware-selection-g2.sh
```



# Install Meshtastic CLI  
https://meshtastic.org/docs/software/python/cli/installation/  
```
cd ~
source meshtastic-venv/bin/activate
pip3 install --upgrade pytap2
pip3 install --upgrade "meshtastic[cli]"
```
OR if not on raspberry pi os 
```
sudo add-apt-repository ppa:meshtastic/daily
sudo apt update
sudo apt install meshtasticd
```

# Rename Device
https://meshtastic.org/docs/software/python/cli/#--set-owner-set_owner
```
deviceShortName=$(meshtastic --info | grep 'Owner' | sed -n 's/.*(\(.*\)).*/\1/p')
echo $deviceShortName

meshtastic --set-owner "G2 mcar NEBell bbsbot DM $deviceShortName"
meshtastic --set-owner-short "🤖"
```


# Set Location
https://meshtastic.org/docs/software/python/cli/#--setalt-setalt
```
meshtastic --setalt 86 --setlat 47.625127 --setlon -122.1019996
```
https://meshtastic.org/docs/configuration/radio/channels/#setting-position-precision
```
meshtastic --ch-set module_settings.position_precision 17 --ch-index 0
```


# Set mode of Device
https://meshtastic.org/docs/configuration/radio/device/#cli
https://meshtastic.org/docs/configuration/module/serial/#serial-module-config-client-availability
```
meshtastic --set device.role ROUTER_LATE
meshtastic --set lora.hop_limit 7
meshtastic --set device.serialEnabled true
```


# Add channels
https://pugetmesh.org/meshtastic/config/#ps-mqtt-channel  
https://meshtastic.org/docs/configuration/radio/channels/
```
source meshtastic-venv/bin/activate
meshtastic --ch-add PS-Mesh!
meshtastic --ch-set psk base64:jHrxpQOq6dEBC5Ldr3ULrQ== --ch-index 1
meshtastic --ch-set module_settings.position_precision 17 --ch-index 1
meshtastic --ch-add PS-MQTT! 
meshtastic --ch-set psk base64:mqttmqttmqttmqttmqttQQ== --ch-index 2
meshtastic --ch-set module_settings.position_precision 17 --ch-index 2
```


# MQTT
https://meshtastic.org/docs/configuration/module/mqtt/#mqtt-module-config-client-availability
```
meshtastic --set network.wifi_enabled true --set network.wifi_ssid "FCC Van" --set network.wifi_psk wifipassword
meshtastic --set lora.config_ok_to_mqtt true
meshtastic --set mqtt.address mqtt.davekeogh.com
meshtastic --set mqtt.username meshdev
meshtastic --set mqtt.password large4cats
meshtastic --set mqtt.encryption_enabled true
meshtastic --set mqtt.json_enabled false
meshtastic --set mqtt.tls_enabled false
meshtastic --set mqtt.root msh/US
meshtastic --set mqtt.map_reporting_enabled true

meshtastic --ch-set uplink_enabled true --ch-index 0
meshtastic --ch-set uplink_enabled true --ch-index 1
meshtastic --ch-set uplink_enabled true --ch-index 2

meshtastic --ch-set downlink_enabled true --ch-index 1
meshtastic --ch-set downlink_enabled true --ch-index 2

meshtastic --set mqtt.enabled true
```

# Disable Bluetooth
https://meshtastic.org/docs/configuration/radio/bluetooth/#bluetooth-config-client-availability
```
meshtastic --set bluetooth.enabled false
```


# Install BBS system.
https://github.com/SpudGunMan/meshing-around

```
cd ~
source meshtastic-venv/bin/activate
git clone https://github.com/spudgunman/meshing-around
cd meshing-around/
./install.sh
cd /opt/meshing-around
./install.sh
```

Are You installing into an embedded system like a luckfox or -native? most should say no here (y/n)n  
Recomended install is in a python virtual environment, do you want to use venv? (y/n)n  
should we add --break-system-packages to the pip install command? (y/n)n  

Which bot do you want to install as a service? Pong Mesh or None? (pong/mesh/n)Mesh  
Do you want to add a local user (meshbot) no login, for the bot? (y/n)y  
Do you want to install the emoji font for debian/ubuntu linux? (y/n)y  
Do you want to install the LLM Ollama components? (y/n)n  



# Exit meshtastic-venv
```
deactivate
```

