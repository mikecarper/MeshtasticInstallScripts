#!/usr/bin/env bash

set -euo pipefail

sudo apt update
sudo apt -y upgrade
sudo apt -y install git jq ntp virtualenvwrapper pipx fonts-noto-color-emoji software-properties-common mosquitto mosquitto-clients 

curl -fsSL https://tailscale.com/install.sh | sh  
sudo tailscale up  


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
            echo "You can continue with other tasks or add a new SSID later."
            ;;
        * )
            echo "Please answer yes or no."
            ;;
    esac
done

sudo nmcli connection show


cd ~
python3 -m venv meshtastic-venv
source meshtastic-venv/bin/activate
pip install --upgrade esptool 
esptool.py chip_id
