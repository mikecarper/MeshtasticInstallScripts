#!/bin/bash
# setup_forwarding.sh
#
# This script sets up port forwarding as follows:
#   - Forwards incoming TCP traffic on port 80 (of the external IP)
#     to the target host's port 8080.
#   - Forwards incoming TCP traffic on port 443 (of the external IP)
#     to the target host's port 8443.
#   - Forwards incoming TCP traffic on port 4403 (of the external IP)
#     to the target host's port 4403.
#
# It performs the following steps:
# 1. Uncomments net.ipv4.ip_forward=1 in /etc/sysctl.conf and reloads sysctl.
# 2. Dynamically determines the local /24 subnet from a non-100, non-127 IP.
# 3. Scans that subnet to find a host with ports 80 and 443 open,
#    setting that as TARGET_IP.
# 4. Finds the external IP from the interface with an IP that starts with "100.".
# 5. Removes any existing iptables DNAT/MASQUERADE rules for these ports.
# 6. Adds new iptables rules to forward:
#       port 80 -> target:8080,
#       port 443 -> target:8443,
#       port 4403 -> target:4403.
# 7. Saves the iptables rules so they persist across reboots.
#
# Note: Ensure that nmap and iptables-persistent (or an alternative persistence
# method) are installed on your system.

set -e

#echo "Uncommenting net.ipv4.ip_forward in /etc/sysctl.conf..."
#sudo sed -i 's/^#\(net\.ipv4\.ip_forward=1\)/\1/' /etc/sysctl.conf

#echo "Reloading sysctl configuration..."
#sudo sysctl -p

echo "Determining local subnet..."
SUBNET=$(ip -o -4 addr list | awk '
  /inet/ {
    split($4, a, "/");
    if (a[1] !~ /^100\./ && a[1] != "127.0.0.1") {
      split(a[1], b, ".");
      print b[1]"."b[2]"."b[3]".0/24"
    }
  }')
echo "Using subnet: $SUBNET"

echo "Scanning subnet for a host with ports 80, 443, and 4403 open..."
TARGET_IP=$(sudo nmap -p 80,443,4403 --open -oG - $SUBNET | \
  awk 'BEGIN {FS="Ports:"} { if($2 ~ /80\/open/ && $2 ~ /443\/open/ && $2 ~ /4403\/open/) print $0 }' | \
  awk -F"Host: " '{print $2}' | awk '{print $1}')
if [ -z "$TARGET_IP" ]; then
  echo "No target host found with ports 80, 443, and 4403 open."
  sudo nmap -p 80,443,4403 --open -oG - $SUBNET
  exit 1
fi
echo "Target IP determined: $TARGET_IP"

echo "Determining external IP (interface with IP starting with 100.)..."
EXTERNAL_IP=$(ip -o -4 addr list | awk '{ if ($4 ~ /^100\./) { split($4,a,"/"); print a[1] } }' | head -n1)
if [ -z "$EXTERNAL_IP" ]; then
  echo "No external IP (starting with 100.) found."
  exit 1
fi
echo "External IP: $EXTERNAL_IP"

echo "Setting iptables rules to forward TCP ports 80,443,4403 from $EXTERNAL_IP to $TARGET_IP..."
# Remove existing rules for these ports, if any
sudo iptables -t nat -D PREROUTING -d $EXTERNAL_IP -p tcp -m multiport --dports 80,443,4403 -j DNAT --to-destination $TARGET_IP 2>/dev/null || true
sudo iptables -t nat -D POSTROUTING -p tcp -m multiport --dports 80,443,4403 -j MASQUERADE 2>/dev/null || true

sudo iptables -t nat -A PREROUTING -d $EXTERNAL_IP -p tcp -m multiport --dports 80,443,4403 -j DNAT --to-destination $TARGET_IP
sudo iptables -t nat -A POSTROUTING -p tcp -m multiport --dports 80,443,4403 -j MASQUERADE


echo "Saving iptables rules..."
# Save using iptables-persistent if available, otherwise use iptables-save.
sudo netfilter-persistent save || sudo iptables-save | sudo tee /etc/iptables/rules.v4

echo "Port forwarding setup complete."

