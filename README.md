Get 64 bit desktop and enable SSH & WiFi from the imager  

# Base pi config
`sudo raspi-config`  
system options -> boot/auto login -> console autologin  

```
sudo apt update
sudo apt -y upgrade
sudo apt -y install git jq ntp virtualenvwrapper pipx fonts-noto-color-emoji software-properties-common mosquitto mosquitto-clients 

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


# Install VPN
100 devices on the free tier  
https://login.tailscale.com/admin/  
```
curl -fsSL https://tailscale.com/install.sh | sh  
curl -fsSL https://tailscale.com/install.sh | sh  
sudo tailscale up  
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


# Add channels
https://pugetmesh.org/meshtastic/config/#ps-mqtt-channel  
```
source meshtastic-venv/bin/activate
meshtastic --ch-add PS-Mesh! --set ch.key jHrxpQOq6dEBC5Ldr3ULrQ==
meshtastic --ch-add PS-Mesh! --set ch.key mqttmqttmqttmqttmqttQQ==

```


# MQTT
```
sudo systemctl enable mosquitto
sudo systemctl start mosquitto
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

