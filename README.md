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
sudo apt -y install git jq ntp virtualenvwrapper pipx fonts-noto-color-emoji npm software-properties-common mosquitto mosquitto-clients python3-poetry socat nmap iptables-persistent shellcheck python3-rpi.gpio screen shfmt i2c-tools tmux cmake libdbus-1-dev 
sudo hostnamectl set-hostname GeoBBS
```


# Install tailscale VPN
100 devices on the free tier  
https://login.tailscale.com/admin/  
```
curl -fsSL https://tailscale.com/install.sh | sh  
curl -fsSL https://tailscale.com/install.sh | sh  
sudo tailscale up  
```

# Port forward node to PI's IP over talescale
```
cd ~
sudo wget -O /usr/local/bin/setup_forwarding.sh https://raw.githubusercontent.com/mikecarper/MeshtasticInstallScripts/main/PortForwardingNode.sh
sudo chmod +x /usr/local/bin/setup_forwarding.sh
/usr/local/bin/setup_forwarding.sh
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


# Update firmware on the g2
https://github.com/mikecarper/meshfirmware
```
cd ~
git clone https://github.com/mikecarper/meshfirmware.git
cd meshfirmware
chmod +x firmware.sh
./firmware.sh
```




# Install Meshtastic CLI  
https://meshtastic.org/docs/software/python/cli/installation/  
```
cd ~
sudo pip3 install --upgrade pyserial --break-system-packages
sudo pip3 install --upgrade pytap2 --break-system-packages
pipx install "meshtastic[cli]"
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
meshtastic --set display.screenOnSecs 5
```


# Add channels
https://pugetmesh.org/meshtastic/config/#ps-mqtt-channel  
https://meshtastic.org/docs/configuration/radio/channels/
```
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


# Setup log viewer
Update html every 5 min
```
#!/bin/bash

NEWCRONJOB="*/5 * * * * /opt/meshing-around/launch.sh html5"

# Check if the cron job is already present; if not, add it.
if crontab -l 2>/dev/null | grep -Fq "$NEWCRONJOB"; then
    echo "Cron job already exists."
else
    # Append the cron job to the existing crontab entries.
    (crontab -l 2>/dev/null; echo "$NEWCRONJOB") | crontab -
    echo "Cron job added."
fi
```

Set the IP to bind to
```
#!/bin/bash
# Get IP from tailscale; if empty then use hostname -I
IP=$(tailscale ip 2>/dev/null | head -n1)
if [ -z "$IP" ]; then
    IP=$(hostname -I | awk '{print $1}')
fi

echo "Using IP: $IP"

# Replace "('127.0.0.1'," with "('$IP'," in /opt/meshing-around/modules/web.py
sed -i "s/HTTPServer(('127\.0\.0\.1',/HTTPServer(('${IP}',/g" /opt/meshing-around/modules/web.py
```

Run as a service that starts automatically. 
```
sudo nano /etc/systemd/system/meshbotweblog.service
```

Put this into that file and save
```
[Unit]
Description=Meshing Around Web Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/meshing-around/modules
ExecStart=/usr/bin/python3 /opt/meshing-around/modules/web.py
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target

```

Enable the service
```
sudo systemctl daemon-reload
sudo systemctl enable meshbotweblog.service
sudo systemctl start meshbotweblog.service
sudo systemctl status meshbotweblog.service
```

# Enable voltage mon
```
pipx install adafruit-circuitpython-ina219 --include-deps
pipx install adafruit-blinka --include-deps
```
![image](https://github.com/user-attachments/assets/ff1bc429-6b1b-420e-bb95-386846212242)

# MeshSense
```
wget https://affirmatech.com/download/meshsense/meshsense-beta-arm64.AppImage
eval $(gnome-keyring-daemon --start --components=secrets)
export GNOME_KEYRING_CONTROL
dbus-run-session xvfb-run ./meshsense-beta-arm64.AppImage --headless --disable-gpu
```



# Enable the live log viewer
Follow the directions found here
https://github.com/mikecarper/MeshtasticInstallScripts/blob/main/logViewerWeb/readme.md
