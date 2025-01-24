Get 64 bit desktop and enable SSH & WiFi from the imager  

# Base pi config
`sudo raspi-config`  
system options -> boot/auto login -> console autologin  

```
sudo apt update
sudo apt -y upgrade
sudo apt -y install git jq virtualenvwrapper pipx fonts-noto-color-emoji
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


# Install BBS system.
https://github.com/SpudGunMan/meshing-around

```cd ~
source meshtastic-venv/bin/activate
git clone https://github.com/spudgunman/meshing-around
cd meshing-around/
./install.sh
cd /opt/meshing-around
`./install.sh
```

Are You installing into an embedded system like a luckfox or -native? most should say no here (y/n)n  
Recomended install is in a python virtual environment, do you want to use venv? (y/n)n  
should we add --break-system-packages to the pip install command? (y/n)n  

Which bot do you want to install as a service? Pong Mesh or None? (pong/mesh/n)Mesh  
Do you want to add a local user (meshbot) no login, for the bot? (y/n)y  
Do you want to install the emoji font for debian/ubuntu linux? (y/n)y  
Do you want to install the LLM Ollama components? (y/n)n  

