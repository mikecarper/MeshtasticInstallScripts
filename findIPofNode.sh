#!/usr/bin/env bash
set -euo pipefail

# 1) Create a temp file and ensure it’s removed on exit
TMPINFO=$(mktemp)
trap 'rm -f "$TMPINFO"' EXIT

# 2) Fetch info once
meshtastic --info > "$TMPINFO"

# 3) Debug: show the full dump (or tail/head if you want less)
echo "[DEBUG] Full meshtastic --info output:" >&2
cat "$TMPINFO" >&2

# 4) Debug: find the myNodeNum line
echo "[DEBUG] myNodeNum line:" >&2
grep '"myNodeNum"' "$TMPINFO" >&2

# 5) Extract the node number
myNodeNum=$(grep '"myNodeNum"' "$TMPINFO" \
             | sed -E 's/.*"myNodeNum":[[:space:]]*([0-9]+).*/\1/')

echo "[DEBUG] Parsed myNodeNum = $myNodeNum" >&2

# 6) Debug: locate the matching "num" line
echo "[DEBUG] num line:" >&2
grep -n "\"num\": $myNodeNum" "$TMPINFO" >&2

# 7) Grab the raw MAC above that line, e.g. "!ffffffff"
raw_mac=$(grep -B1 "\"num\": $myNodeNum" "$TMPINFO" \
          | head -1 \
          | sed -E 's/.*"(![0-9A-Fa-f]+)".*/\1/')

# 8) Strip the leading "!"
raw_mac=${raw_mac#!}

# 9) Insert ":" every two hex digits
formatted_mac=$(echo "$raw_mac" | sed -E 's/../&:/g; s/:$//')

# 10) Print the cleaned‐up MAC
echo "$formatted_mac"
