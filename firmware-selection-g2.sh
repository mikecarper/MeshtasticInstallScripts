#!/usr/bin/env bash
#
# select_meshtastic_firmware.sh
#
# Bash script to fetch releases from meshtastic/firmware on GitHub,
# display available versions (including alpha/beta/rc info),
# and let the user pick which release to download.
# Specifically filters assets that contain "esp32s3", end with ".zip",
# and do NOT contain "debug" in the filename.
#
# If there's only one matching asset, automatically downloads it.

set -euo pipefail

REPO_OWNER="meshtastic"
REPO_NAME="firmware"
API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases"

echo "Fetching releases from GitHub: ${REPO_OWNER}/${REPO_NAME} ..."
releases_json=$(curl -s "${API_URL}")

if [ -z "$releases_json" ]; then
  echo "Failed to fetch release data. Check your internet or GitHub API status."
  exit 1
fi

# Parse each release into a compact JSON object:
mapfile -t releases_info < <(echo "$releases_json" | jq -c '.[] | {
    tag_name,
    prerelease,
    draft
}')

if [ ${#releases_info[@]} -eq 0 ]; then
  echo "No releases found. Exiting."
  exit 1
fi

declare -a versions_tags=()
declare -a versions_labels=()

for release_json in "${releases_info[@]}"; do
  tag_name=$(echo "$release_json" | jq -r '.tag_name')
  prerelease=$(echo "$release_json" | jq -r '.prerelease')
  draft=$(echo "$release_json" | jq -r '.draft')

  suffix=""
  # Check for alpha, beta, rc in the tag_name:
  if [[ "$tag_name" =~ [Aa]lpha ]]; then
    suffix="(alpha)"
  elif [[ "$tag_name" =~ [Bb]eta ]]; then
    suffix="(beta)"
  elif [[ "$tag_name" =~ [Rr][Cc] ]]; then
    suffix="(rc)"
  fi

  # If GitHub prerelease flag is set but no alpha/beta/rc found,
  # label it as (pre-release). Also handle draft.
  if [ "$draft" = "true" ]; then
    suffix="(draft)"
  elif [ "$prerelease" = "true" ] && [ -z "$suffix" ]; then
    suffix="(pre-release)"
  fi

  label="$tag_name"
  [ -n "$suffix" ] && label="$label $suffix"

  versions_tags+=("$tag_name")
  versions_labels+=("$label")
done

echo ""
echo "Available firmware versions:"
select chosen_label in "${versions_labels[@]}"; do
  if [[ -n "$chosen_label" ]]; then
    echo "You selected: $chosen_label"
    break
  else
    echo "Invalid selection. Please pick a number from the list."
  fi
done

# Find out which index was chosen
chosen_index=$((REPLY-1))
chosen_tag="${versions_tags[$chosen_index]}"

echo ""
echo "Fetching assets for release: $chosen_tag"

# Filter: must contain "esp32s3", end with ".zip", and NOT contain "debug"
mapfile -t download_urls < <(
  echo "$releases_json" \
  | jq -r --arg VERSION "$chosen_tag" '
      .[] 
      | select(.tag_name == $VERSION) 
      | .assets[]
      | select(
          (.name | test("esp32s3"; "i"))    # contains "esp32s3" (case-insensitive)
          and (.name | endswith(".zip"))    # ends with ".zip"
          and ((.name | test("debug"; "i")) | not)  # does NOT contain "debug"
        )
      | .browser_download_url
    '
)

count_matches=${#download_urls[@]}

if [ "$count_matches" -eq 0 ]; then
  echo "No matching zip assets (esp32s3, not debug) found for tag: $chosen_tag"
  exit 1
elif [ "$count_matches" -eq 1 ]; then
  # If there's exactly 1 matching asset, download automatically
  echo "Found 1 matching .zip asset:"
  selected_url="${download_urls[0]}"

else
  # If there's more than one, prompt to select
  echo "Available firmware files for $chosen_tag (zip with 'esp32s3', not 'debug'):"
  for i in "${!download_urls[@]}"; do
    echo "$((i+1)). ${download_urls[$i]}"
  done

  echo ""
  read -r -p "Select which zip file to download by number: " asset_index

  if ! [[ "$asset_index" =~ ^[0-9]+$ ]] || [ "$asset_index" -lt 1 ] || [ "$asset_index" -gt "$count_matches" ]; then
    echo "Invalid choice. Exiting."
    exit 1
  fi

  selected_url="${download_urls[$((asset_index-1))]}"

fi

echo "Selected download URL: $selected_url"
filename=$(basename "$selected_url")
echo "Downloading firmware to $filename ..."
curl -sSL -o "$filename" "$selected_url"
echo "Download complete! File saved to: $(pwd)/${filename}"
rm -rf g2
mkdir -p g2
unzip "${filename}" "device-update.sh" "*station-g2*update*" -d ~/g2/

source meshtastic-venv/bin/activate

while true; do
  # Check lsusb for a device matching 'g2' (case-insensitive).
  if lsusb | grep -qi "g2"; then
    echo "G2 device found!"
    break
  else
    echo "G2 device NOT found."
    read -r -p "Check again? (y/n): " choice
    case "$choice" in
      [Yy]* ) continue ;;   # Loop again to check
      * ) 
        echo "Exiting..."
        exit 0
        ;;
    esac
  fi
done

FIRMWARE_FILE=$(ls ~/g2 | grep "station-g2.*update")
sleep 2
esptool.py -b1200 chip_id
echo "./g2/device-update.sh -f ~/g2/$FIRMWARE_FILE"
sed -i 's/--baud 115200/--baud 1200/g' ~/g2/device-update.sh

./g2/device-update.sh -f ~/g2/"$FIRMWARE_FILE"


echo "Done." 
