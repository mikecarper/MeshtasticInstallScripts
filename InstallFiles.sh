#!/usr/bin/env bash

set -euo pipefail
echo "Update"
sudo apt update

echo "Upgrade"
sudo apt -y upgrade

echo "apt packages"
sudo apt -y install git jq ntp virtualenvwrapper pipx fonts-noto-color-emoji software-properties-common mosquitto mosquitto-clients 

echo "tailscale vpn"
curl -fsSL https://tailscale.com/install.sh | sh  
sudo tailscale up  

echo "add wifi networks"
# Function to display a menu of available Wi-Fi networks
function display_wifi_menu {
    echo "Scanning for Wi-Fi networks..."
    
    # Use nmcli to list available Wi-Fi networks
    mapfile -t wifi_list < <(sudo nmcli dev wifi list | awk 'NR>1 {print $2}' | grep -v "^--")

    if [[ ${#wifi_list[@]} -eq 0 ]]; then
        echo "No Wi-Fi networks found."
        exit 1
    fi

    echo "Available Wi-Fi networks:"
    for i in "${!wifi_list[@]}"; do
        echo "$((i + 1)). ${wifi_list[$i]}"
    done
}

# Function to select an SSID
function select_ssid {
    while true; do
        read -p "Select the number corresponding to the Wi-Fi network: " ssid_choice

        if [[ $ssid_choice =~ ^[0-9]+$ ]] && [[ $ssid_choice -ge 1 ]] && [[ $ssid_choice -le ${#wifi_list[@]} ]]; then
            ssid="${wifi_list[$((ssid_choice - 1))]}"
            echo "You selected: $ssid"
            break
        else
            echo "Invalid choice. Please select a valid number from the menu."
        fi
    done
}

# Function to prompt for a Wi-Fi password
function prompt_password {
    read -sp "Enter the Wi-Fi password (plaintext): " wifi_password
    echo # New line for better readability
}

#!/bin/bash

# Check for Wi-Fi hardware
if dmesg | grep -iq "wifi"; then
    echo "Wi-Fi hardware detected."
    # Additional commands if Wi-Fi hardware exists
    
	sudo nmcli connection show
	# Main script execution wrapped in a y/n question
	while true; do
	    read -p "Do you want to add a new SSID? (y/n): " add_ssid_choice
	    case $add_ssid_choice in
	        [Yy]* )
	            display_wifi_menu
	            select_ssid
	            prompt_password
	
	            # Attempt to connect to the selected Wi-Fi network
	            sudo nmcli dev wifi connect "$ssid" password "$wifi_password"
	
	            # Check if the connection was successful
	            if [[ $? -eq 0 ]]; then
	                echo "Successfully connected to $ssid."
	            else
	                echo "Failed to connect to $ssid. Please check the password and try again."
	            fi
	            ;;
	        [Nn]* )
				break
	            ;;
	        * )
	            echo "Please answer yes or no."
	            ;;
	    esac
	done
	
	sudo nmcli connection show
else
    echo "No Wi-Fi hardware detected."
    # Additional commands if Wi-Fi hardware is not found
fi


echo "python3 -m venv"
cd ~
python3 -m venv meshtastic-venv
source meshtastic-venv/bin/activate

echo "esptool"
pip install --upgrade esptool 
#esptool.py chip_id

cd ~
source meshtastic-venv/bin/activate
echo "pytap2"
pip3 install --upgrade pytap2
echo "meshtastic cli"
pip3 install --upgrade "meshtastic[cli]"

cd ~
echo "spudgunman bbs"
source meshtastic-venv/bin/activate
git clone https://github.com/spudgunman/meshing-around
chmod +x ~/meshing-around/install.sh

deactivate

~/meshing-around/install.sh << EOF
y
EOF

sudo /opt/meshing-around/install.sh << EOF
n
y
mesh
y
y
n

n
EOF

echo "linux owmership for bbs"
sudo chmod -R a+rw /opt/meshing-around/
sudo usermod -aG plugdev meshbot
groups meshbot

#!/bin/bash

config_file="/opt/meshing-around/config.ini"

# Ensure the file exists
if [[ ! -f "$config_file" ]]; then
    echo "Error: Config file not found at $config_file"
    exit 1
fi

# Use sed to update the values in the config file
sed -i \
    -e 's/^DadJokesEmoji = False/DadJokesEmoji = True/' \
    -e 's/^spaceWeather = True/spaceWeather = False/' \
    -e 's/^wikipedia = True/wikipedia = False/' \
    -e 's/^SentryEnabled = True/SentryEnabled = False/' \
    -e 's/^dopeWars = True/dopeWars = False/' \
    -e 's/^lemonade = True/lemonade = False/' \
    -e 's/^blackjack = True/blackjack = False/' \
    -e 's/^videopoker = True/videopoker = False/' \
    -e 's/^mastermind = True/mastermind = False/' \
    -e 's/^golfsim = True/golfsim = False/' \
    "$config_file"

# Print a message to confirm
echo "Config file updated successfully."

echo "mesh_bot systemctl"
sudo systemctl daemon-reload
sudo systemctl enable mesh_bot
sudo systemctl start mesh_bot
sudo systemctl status mesh_bot

sudo reboot
