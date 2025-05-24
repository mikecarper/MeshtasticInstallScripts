#!/usr/bin/env bash

set -euo pipefail

# Ensure protoc is present
if ! command -v protoc >/dev/null 2>&1; then
    echo "protobuf-compiler not found – installing..."
    sudo apt update && sudo apt install -y protobuf-compiler
fi



PROTO_DIR="$HOME/meshtastic-protobufs"        # git clone https://github.com/meshtastic/protobufs.git
PROTO_FILE="meshtastic/apponly.proto"                    # contains ChannelSet definition

URL="$1"                                      # share-URL passed on the cmd-line

if [ ! -d "$PROTO_DIR" ]; then
    echo "Meshtastic protobuf folder not found – cloning..."
    git clone https://github.com/meshtastic/protobufs.git "$PROTO_DIR"
fi


# ---------- extract & pad base-64  ----------
b64=${URL##*#}
case $(( ${#b64} % 4 )) in
  2) b64+='==' ;;
  3) b64+='='  ;;
esac

# >>> convert URL-safe alphabet to standard <<<
b64=${b64//-/+}           # '-' → '+'
b64=${b64//_/\/}          # '_' → '/'

# ---------- decode & show ----------
tmp=$(mktemp)
echo "$b64" | base64 -d > "$tmp"

echo "Decoded ChannelSet:"

# ---- extract PSK line from the text-format output ----
decoded=$( protoc --proto_path="$PROTO_DIR" --decode=meshtastic.ChannelSet meshtastic/apponly.proto < "$tmp" )
echo "$decoded"

printf '%s\n' "$decoded" \
  | grep -oP 'psk:\s*"\K[^"]+' \
  | while read -r psk_escaped; do
        # turn C-escapes into raw bytes, then base-64
        psk_b64=$(printf '%b' "$psk_escaped" | base64 -w0)
        echo "psk (base64): $psk_b64"
    done


rm "$tmp"

