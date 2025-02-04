#!/usr/bin/env bash
#
# select_meshtastic_firmware.sh
#
# This script:
# 1. Checks for an internet connection and updates a cache file (if older than 6 hours)
#    with GitHub release data for meshtastic/firmware.
# 2. Presents a menu of release versions (including alpha/pre-releases) to choose from.
# 3. For the chosen release version, ensures that all firmware zip assets (those whose names
#    start with "firmware-" and end with the version string) are downloaded.
# 4. Unzips missing assets into a folder structure: firmware/<version>/<product>/.
# 5. Searches the downloaded firmware (by filename) to extract the product name.
# 6. Uses lsusb output to detect the connected device’s product.
# 7. If more than one firmware file matches the detected product, prompts the user to select one.
# 8. Asks whether to update (default) or install.
#
# Adjust regular expressions and commands as needed for your environment.

set -euo pipefail

# Configuration
REPO_OWNER="meshtastic"
REPO_NAME="firmware"
GITHUB_API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases"
CACHE_TIMEOUT_SECONDS=$((6 * 3600))  # 6 hours
PWD_SCRIPT="$(pwd)"
DOWNLOAD_DIR="${PWD_SCRIPT}/firmware_downloads"  # Current working directory for downloads
FIRMWARE_ROOT="${PWD_SCRIPT}/firmware"
CACHE_FILE="${FIRMWARE_ROOT}/meshtastic_firmware_releases.json"

# Function: Check internet connectivity
check_internet() {
    if ping -c1 -W2 api.github.com > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

normalize() {
  # Remove dashes, underscores, and spaces, then convert to lowercase
  echo "$1" | sed 's/[-_ ]//g' | tr '[:upper:]' '[:lower:]'
}


# Update cache if necessary
update_cache() {
    if check_internet; then
        if [ ! -f "$CACHE_FILE" ] || [ "$(date +%s)" -ge "$(( $(stat -c %Y "$CACHE_FILE") + CACHE_TIMEOUT_SECONDS ))" ]; then
			#read -p "Press enter to continue"
			mkdir -p $FIRMWARE_ROOT
            echo "Updating release cache from GitHub..."
            curl -s "$GITHUB_API_URL" -o "$CACHE_FILE"
        else
            echo "Using cached release data (updated within the last 6 hours)."
        fi
    else
        echo "No internet connection; using cached release data if available."
    fi
}

update_cache

# Load release data
if [ ! -f "$CACHE_FILE" ]; then
    echo "No cached release data available. Exiting."
    exit 1
fi

releases_json=$(cat "$CACHE_FILE")

# Build a list of release versions (using tag names) with labels (append (alpha), etc)
declare -a versions_tags=()
declare -a versions_labels=()
echo "Parsing Release JSON data"
mapfile -t release_items < <(echo "$releases_json" | jq -c '.[]')
if [ ${#release_items[@]} -eq 0 ]; then
    echo "No releases found. Exiting."
    exit 1
fi

echo "Building Release JSON menu"
for item in "${release_items[@]}"; do
    tag=$(echo "$item" | jq -r '.tag_name')
    prerelease=$(echo "$item" | jq -r '.prerelease')
    draft=$(echo "$item" | jq -r '.draft')
    suffix=""
    if [[ "$tag" =~ [Aa]lpha ]]; then
        suffix="(alpha)"
    elif [[ "$tag" =~ [Bb]eta ]]; then
        suffix="(beta)"
    elif [[ "$tag" =~ [Rr][Cc] ]]; then
        suffix="(rc)"
    fi
    if [ "$draft" = "true" ]; then
        suffix="(draft)"
    elif [ "$prerelease" = "true" ] && [ -z "$suffix" ]; then
        suffix="(pre-release)"
    fi
    label="$tag"
    [ -n "$suffix" ] && label="$label $suffix"
    versions_tags+=("$tag")
    versions_labels+=("$label")
done

echo ""
echo "Available firmware release versions:"
select chosen_release in "${versions_labels[@]}"; do
  if [[ -n "$chosen_release" ]]; then
    echo "You selected: $chosen_release"
    break
  else
    echo "Invalid selection. Please choose a number."
  fi
done

chosen_index=$((REPLY - 1))
chosen_tag="${versions_tags[$chosen_index]}"
echo "Chosen release version: $chosen_tag"

# For the chosen release, get all assets whose name starts with "firmware-" and ends with the version string.
# For example, look for filenames like: firmware-<product>-<versionSuffix>.zip
# Assume version string appears in the filename after a dash.
download_pattern="-${chosen_tag}"
echo "Searching for firmware assets for release $chosen_tag..."
mapfile -t assets < <(
  echo "$releases_json" | jq -r --arg TAG "$chosen_tag" '
    .[] | select(.tag_name==$TAG) | .assets[] |
    select(.name | test("^firmware-"; "i")) |
    select(.name | test("debug"; "i") | not) |
    {name: .name, url: .browser_download_url} | @base64'
)

if [ ${#assets[@]} -eq 0 ]; then
  echo "No firmware assets found for release $chosen_tag matching criteria."
  exit 1
fi

# For each asset, check if the file has been downloaded.
# Download any missing firmware assets.
mkdir -p $DOWNLOAD_DIR
echo ""
for asset in "${assets[@]}"; do
    decoded=$(echo "$asset" | base64 --decode)
    asset_name=$(echo "$decoded" | jq -r '.name')
    asset_url=$(echo "$decoded" | jq -r '.url')
    local_file="${DOWNLOAD_DIR}/${asset_name}"
    if [ -f "$local_file" ]; then
        echo "Firmware asset $asset_name already downloaded."
    else
        echo "Downloading firmware asset $asset_name to $local_file ..."
        curl -sSL -o "$local_file" "$asset_url"
        #echo "Downloaded $asset_name."
    fi
done

# Unzip each firmware asset into folder structure: firmware/<release_version>/<product>/
echo ""
echo "Unzipping firmware assets..."
for asset in "${assets[@]}"; do
    decoded=$(echo "$asset" | base64 --decode)
    asset_name=$(echo "$decoded" | jq -r '.name')
    local_file="${DOWNLOAD_DIR}/${asset_name}"
    # Expect filename format: firmware-<product>-<versionSuffix>.zip
    if [[ "$asset_name" =~ ^firmware-([^-\ ]+)-(.+)\.zip$ ]]; then
        product="${BASH_REMATCH[1]}"
        version_suffix="${BASH_REMATCH[2]}"
        # Create folder: firmware/<chosen_tag>/<product>/
        target_dir="${FIRMWARE_ROOT}/${chosen_tag}/${product}"
        mkdir -p "$target_dir"
        if [ -z "$(ls -A "$target_dir" 2>/dev/null)" ]; then
            echo "Unzipping $asset_name into $target_dir ..."
            unzip -o "$local_file" -d "$target_dir"
        else
            echo "Files already exist in $target_dir; skipping unzip for $asset_name."
        fi
    else
        echo "Asset $asset_name does not match expected naming convention. Skipping unzip."
    fi
done


# Search all firmware/<chosen_tag> for files matching:
# filenames starting with "firmware-" and ending with "$download_pattern.zip"
# Extract the product name from the middle of the filename.
# Remove the "v" from download_pattern for filename matching.
pattern_without_v=$(echo "$download_pattern" | sed 's/v//g')

echo ""
echo "Scanning extracted firmware for matching products..."
declare -A product_files
# Search under the extracted folder for the chosen release.
while IFS= read -r -d '' file; do
    fname=$(basename "$file")
    #echo "Checking file: $fname"
    # Use a regex that captures everything between "firmware-" and the pattern_without_v.
    # This regex is greedy, so it will capture all characters up to the last occurrence of pattern_without_v.
    # Then we trim any trailing dash/underscore/space.
    if [[ "$fname" =~ ^firmware-(.*)${pattern_without_v}(-update)?\.(bin|uf2|hex|zip)$ ]]; then
        prod="${BASH_REMATCH[1]}"
        # Remove any trailing dashes, underscores, or spaces.
        prod=$(echo "$prod" | sed 's/[-_ ]*$//')
        product_files["$prod"]+="$file"$'\n'
    fi
done < <(find "$FIRMWARE_ROOT/${chosen_tag}" -type f -iname "firmware-*" -print0)

# Now detect the connected device via lsusb.
echo ""
echo "Detecting connected device via lsusb..."
lsusb_output=$(lsusb)
# Extract the device description (everything after the ID field).
detected_raw=$(echo "$lsusb_output" | sed -n 's/.*ID [0-9a-fA-F]\{4\}:[0-9a-fA-F]\{4\} //p' | head -n1)
# Extract the last two words from the description, which usually represent the product.
detected_product=$(echo "$detected_raw" | awk '{print $(NF-1), $NF}')
# Normalize the extracted product string.
detected_product=$(normalize "$detected_product")
if [ -z "$detected_product" ]; then
    echo "Could not detect device product via lsusb. Exiting."
    exit 1
fi
echo "Detected product (normalized): $detected_product"

echo ""
echo "Matching firmware products with detected device product..."
matching_keys=()
for prod in "${!product_files[@]}"; do
    norm_prod=$(normalize "$prod")
    # Check if the normalized product matches the detected product.
    # This uses a substring match in either direction.
    if [[ "$norm_prod" == *"$detected_product"* ]] || [[ "$detected_product" == *"$norm_prod"* ]]; then
        echo "Product match: $prod (normalized: $norm_prod)"
        matching_keys+=("$prod")
    #else
        #echo "No match for: $prod (normalized: $norm_prod) against detected: $detected_product"
    fi

done

# ----- Step 4: Find matching firmware files based on detected product -----
IFS=$'\n' read -r -d '' -a matching_files < <(
  for key in "${matching_keys[@]}"; do
    echo "${product_files[$key]}"
  done
  printf '\0'
)

if [ ${#matching_files[@]} -eq 0 ]; then
    echo "No firmware files match the detected product ($detected_product). Exiting."
    exit 1
elif [ ${#matching_files[@]} -eq 1 ]; then
    selected_file="${matching_files[0]}"
    echo "One matching firmware file found: $selected_file"
else
    echo "Multiple matching firmware files found:"
    for i in "${!matching_files[@]}"; do
        echo "$((i+1)). ${matching_files[$i]}"
    done
    read -r -p "Select which firmware file to use [1-${#matching_files[@]}]: " file_choice
    if ! [[ "$file_choice" =~ ^[0-9]+$ ]] || [ "$file_choice" -lt 1 ] || [ "$file_choice" -gt "${#matching_files[@]}" ]; then
        echo "Invalid selection. Exiting."
        exit 1
    fi
    selected_file="${matching_files[$((file_choice-1))]}"
fi

echo ""
echo "Selected firmware file for operation: $selected_file"


# Ask whether to update or install (default is update)
read -r -p "Do you want to (u)pdate [default] or (i)nstall? [u/i]: " op_choice
op_choice=${op_choice:-u}
if [[ "$op_choice" =~ ^[Ii] ]]; then
  operation="install"
else
  operation="update"
fi
echo "Operation chosen: $operation"

# Determine the script to run based on the operation.
if [ "$operation" = "update" ]; then
  script_to_run="$(dirname "$selected_file")/device-update.sh"
elif [ "$operation" = "install" ]; then
  script_to_run="$(dirname "$selected_file")/device-install.sh"
fi

# If the firmware file is for ESP32 (filename contains "esp32"), then modify the update script baud rate.
if echo "$selected_file" | grep -qi "esp32"; then
    if [ -f "$script_to_run" ]; then
        echo "Modifying baud rate in $(basename "$script_to_run") for ESP32 firmware..."
        sed -i 's/--baud 115200/--baud 1200/g' "$script_to_run"
    else
        echo "No $(basename "$script_to_run") found in $(dirname "$selected_file"). Skipping baud rate change."
    fi
fi

# Ensure the chosen script has the executable bit set.
if [ ! -x "$script_to_run" ]; then
    echo "Setting executable bit on $(basename "$script_to_run")..."
    chmod +x "$script_to_run"
fi

# Build absolute paths for the script and the firmware file.
abs_script="$(cd "$(dirname "$script_to_run")" && pwd)/$(basename "$script_to_run")"
abs_selected="$(cd "$(dirname "$selected_file")" && pwd)/$(basename "$selected_file")"

# Build the command.
cmd="$abs_script -f $abs_selected"

echo ""
echo "Command to run for firmware ${operation}:"
echo "$cmd"
