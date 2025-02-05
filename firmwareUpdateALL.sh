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
#PWD_SCRIPT="$(pwd)"
PWD_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOAD_DIR="${PWD_SCRIPT}/firmware_downloads"  # Current working directory for downloads
FIRMWARE_ROOT="${PWD_SCRIPT}/firmware"
CACHE_FILE="${FIRMWARE_ROOT}/meshtastic_firmware_releases.json"

# Function to display help
show_help() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo
    echo "Options:"
    echo "  --version VERSION   Specify the version to use."
    echo "  --install           Set the operation to 'install'."
    echo "  --update            Set the operation to 'update'."
    echo "  --run               Automatically run the update script without prompting."
    echo "  -h, --help          Display this help message and exit."
    echo
    exit 0
}

# Initialize variables
VERSION_ARG=""
OPERATION_ARG=""
RUN_UPDATE=false

# Process command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            shift
            VERSION_ARG="$1"
            ;;
        --install)
            if [ -n "$OPERATION_ARG" ] && [ "$OPERATION_ARG" != "install" ]; then
                echo "Error: Conflicting options specified."
                exit 1
            fi
            OPERATION_ARG="install"
            ;;
        --update)
            if [ -n "$OPERATION_ARG" ] && [ "$OPERATION_ARG" != "update" ]; then
                echo "Error: Conflicting options specified."
                exit 1
            fi
            OPERATION_ARG="update"
            ;;
        --run)
            RUN_UPDATE=true
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
    shift
done

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
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:blank:]' | tr -d '-' | tr -d '_'
}


# Update cache if necessary
update_cache() {
    if check_internet; then
        if [ ! -f "$CACHE_FILE" ] || [ "$(date +%s)" -ge "$(( $(stat -c %Y "$CACHE_FILE") + CACHE_TIMEOUT_SECONDS ))" ]; then
			#read -p "Press enter to continue"
			mkdir -p "$FIRMWARE_ROOT"
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
echo -n "Parsing JSON; "
mapfile -t release_items < <(echo "$releases_json" | jq -c '.[]')
if [ ${#release_items[@]} -eq 0 ]; then
    echo "No releases found. Exiting."
    exit 1
fi

echo -n "Building Menu"
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
	echo -n "."
done
echo ""

# Auto-select based on the --version argument if provided.
if [ -n "$VERSION_ARG" ]; then
    auto_selected=""
    for i in "${!versions_tags[@]}"; do
        # Check if the version tag contains the provided version argument.
        if [[ "${versions_tags[$i]}" == *${VERSION_ARG}* ]]; then
            auto_selected="${versions_labels[$i]}"
            chosen_index=$i
            #echo "Auto-selected firmware release: ${versions_tags[$i]} (${versions_labels[$i]})"
            break
        fi
    done
    if [ -z "$auto_selected" ]; then
        echo "No release version found matching --version $VERSION_ARG"
        exit 1
    fi
    chosen_release="$auto_selected"
else
	echo ""
    # Otherwise, present the interactive menu.
    echo "Available firmware release versions:"
    select chosen_release in "${versions_labels[@]}"; do
        if [[ -n "$chosen_release" ]]; then
            chosen_index=$((REPLY - 1))
            break
        else
            echo "Invalid selection. Please choose a number."
        fi
    done
fi

# Continue with the rest of the script using $chosen_release.
echo "You selected: $chosen_release"

chosen_tag="${versions_tags[$chosen_index]}"
#echo "Chosen release version tag: $chosen_tag"

# For the chosen release, get all assets whose name starts with "firmware-" and ends with the version string.
# For example, look for filenames like: firmware-<product>-<versionSuffix>.zip
# Assume version string appears in the filename after a dash.
download_pattern="-${chosen_tag}"
#echo "Searching for firmware assets for release $chosen_tag..."
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
mkdir -p "$DOWNLOAD_DIR"
StreamOutput=0
for asset in "${assets[@]}"; do
    decoded=$(echo "$asset" | base64 --decode)
    asset_name=$(echo "$decoded" | jq -r '.name')
    asset_url=$(echo "$decoded" | jq -r '.url')
    local_file="${DOWNLOAD_DIR}/${asset_name}"
    if [ -f "$local_file" ]; then
		if [ $StreamOutput -eq 0 ]
		then
			echo -n "Already downloaded $asset_name "
			StreamOutput=1
		else
			echo -n "$asset_name "
		fi
		
    else
		if [ $StreamOutput -eq 1 ]
		then
			echo ""
		fi
        echo "Downloading $asset_name to $local_file ..."
        curl -sSL -o "$local_file" "$asset_url"
        #echo "Downloaded $asset_name."
    fi
done
echo ""

# Unzip each firmware asset into folder structure: firmware/<release_version>/<product>/
echo "Unzipping firmware assets..."
StreamOutput=0
for asset in "${assets[@]}"; do
    decoded=$(echo "$asset" | base64 --decode)
    asset_name=$(echo "$decoded" | jq -r '.name')
    local_file="${DOWNLOAD_DIR}/${asset_name}"
    # Expect filename format: firmware-<product>-<versionSuffix>.zip
    if [[ "$asset_name" =~ ^firmware-([^-\ ]+)-(.+)\.zip$ ]]; then
        product="${BASH_REMATCH[1]}"
        #version_suffix="${BASH_REMATCH[2]}"
        # Create folder: firmware/<chosen_tag>/<product>/
        target_dir="${FIRMWARE_ROOT}/${chosen_tag}/${product}"
        mkdir -p "$target_dir"
        if [ -z "$(ls -A "$target_dir" 2>/dev/null)" ]; then
			if [ $StreamOutput -eq 1 ]
			then
				echo ""
			fi
            echo "Unzipping $asset_name into $target_dir ..."
            unzip -o "$local_file" -d "$target_dir"
			StreamOutput=0
        else
			if [ $StreamOutput -eq 0 ]
			then
				echo -n "Files already exist for $asset_name "
				StreamOutput=1
			else
				echo -n "$asset_name "
			fi
        fi
    else
        echo "Asset $asset_name does not match expected naming convention. Skipping unzip."
    fi
done
echo ""


# Search all firmware/<chosen_tag> for files matching:
# filenames starting with "firmware-" and ending with "$download_pattern.zip"
# Extract the product name from the middle of the filename.
# Remove the "v" from download_pattern for filename matching.
pattern_without_v="${download_pattern//v/}"


#echo ""
#echo "Scanning extracted firmware for matching products..."
declare -A product_files
declare -A product_files_full
# Search under the extracted folder for the chosen release.
while IFS= read -r -d '' file; do
    fname=$(basename "$file")
    #echo "Checking file: $fname"
    # Use a regex that captures everything between "firmware-" and the pattern_without_v.
    # This regex is greedy, so it will capture all characters up to the last occurrence of pattern_without_v.
    # Then we trim any trailing dash/underscore/space.
    if [[ "$fname" =~ ^firmware-(.*)${pattern_without_v}(-update)?\.(bin|uf2|zip)$ ]]; then
        prod="${BASH_REMATCH[1]}"
        # Remove any trailing dashes, underscores, or spaces.
		prodNorm=$(normalize "$prod")
        product_files["$prodNorm"]+="$file"$'\n'
		product_files_full["$prodNorm"]+="$prod"$'\n'
    fi
done < <(find "$FIRMWARE_ROOT/${chosen_tag}" -type f -iname "firmware-*" -print0)

# Now detect the connected device via lsusb.
echo ""
#echo "Detecting connected device via lsusb..."

# Get the lsusb output.
lsusb_output=$(lsusb)

# Extract the device description (everything after the "ID ..." field)
mapfile -t all_device_lines < <(echo "$lsusb_output" | sed -n 's/.*ID [0-9a-fA-F]\{4\}:[0-9a-fA-F]\{4\} //p')

# Filter out lines that contain "hub" (case-insensitive).
filtered_device_lines=()
for line in "${all_device_lines[@]}"; do
    if ! echo "$line" | grep -qi "hub"; then
        filtered_device_lines+=("$line")
    fi
done

# If filtering out "hub" devices yields no matches, fall back to using all devices.
if [ "${#filtered_device_lines[@]}" -eq 0 ]; then
    filtered_device_lines=("${all_device_lines[@]}")
fi

# Determine which device to use.
if [ "${#filtered_device_lines[@]}" -eq 0 ]; then
    echo "No matching USB devices found."
    detected_product=""
    exit 1
elif [ "${#filtered_device_lines[@]}" -eq 1 ]; then
    # Only one match: select it.
    detected_raw="${filtered_device_lines[0]}"
else
    # More than one match: present a menu for the user to choose.
    echo "Multiple USB devices detected:"
    for idx in "${!filtered_device_lines[@]}"; do
        printf "%d) %s\n" $((idx+1)) "${filtered_device_lines[$idx]}"
    done

    # Loop until a valid selection is made.
    while true; do
        read -rp "Please select a device [1-${#filtered_device_lines[@]}]: " selection
        if [[ "$selection" =~ ^[1-9][0-9]*$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#filtered_device_lines[@]}" ]; then
            detected_raw="${filtered_device_lines[$((selection-1))]}"
            break
        else
            echo "Invalid selection. Try again."
        fi
    done
fi

echo "Found: $detected_raw"
# Normalize the product string.
detected_product=$(normalize "$detected_raw")

# Show the final detected product.
#echo "Detected product: $detected_product"


#echo ""
#echo "Matching firmware products with detected device product..."
matching_keys=()
for prod in "${!product_files[@]}"; do
    norm_prod=$(normalize "$prod")
	#echo "${detected_product} ${norm_prod}"
    # Check if the normalized product matches the detected product.
    # This uses a substring match in either direction.
	#echo "${detected_product}" | grep "$norm_prod"
    if [[ "$norm_prod" == *"$detected_product"* ]] || [[ "$detected_product" == *"$norm_prod"* ]]; then
		ProdFile=$( echo "${product_files_full[$prod]}" | head -n1 )
        echo "Firmware file match on: $ProdFile"
		
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

	USBproduct=$(lsusb -v 2>/dev/null \
    | grep "iProduct" \
    | grep -vi "Controller" \
    | sed -n 's/.*2[[:space:]]\+\([^[:space:]]\+\).*/\1/p' \
    | head -n 1 \
    | tr '[:upper:]' '[:lower:]')
	
	echo "Doing a deep search for $USBproduct in $FIRMWARE_ROOT/${chosen_tag}/*"
	# Capture all matching file paths (each on a new line)
	found_files=$(grep -aFrin --exclude="*-ota.zip" "$USBproduct" "$FIRMWARE_ROOT/${chosen_tag}" | cut -d: -f1)

	if [ -z "$found_files" ]; then
		echo "No firmware files match the detected product ($detected_product) ($USBproduct). Exiting."
		exit 1
	fi
	
	# Populate matching_files array with all found file paths.
	IFS=$'\n' read -r -d '' -a matching_files < <(
		echo "$found_files"
		printf '\0'
	)

fi


# Set operation from command-line argument if provided; otherwise prompt interactively.
if [ -n "$OPERATION_ARG" ]; then
    operation="$OPERATION_ARG"
else
    # Ask whether to update or install (default is update)
    read -r -p "Do you want to (u)pdate [default] or (i)nstall? [U/i]: " op_choice
    op_choice=${op_choice:-u}
    if [[ "$op_choice" =~ ^[Ii] ]]; then
        operation="install"
    else
        operation="update"
    fi
fi
echo "Operation chosen: $operation"

# Filter matching files based on the operation
if [[ "$operation" == "update" ]]; then
    # Prioritize files ending with '-update.*' for update operation
    update_files=()
    other_files=()
    for file in "${matching_files[@]}"; do
        if [[ "$file" == *-update.* ]]; then
            update_files+=("$file")
        else
            other_files+=("$file")
        fi
    done
    # Use update files if available, otherwise fall back to other files
    if [[ ${#update_files[@]} -gt 0 ]]; then
        matching_files=("${update_files[@]}")
    else
        matching_files=("${other_files[@]}")
    fi
fi

if [ ${#matching_files[@]} -eq 1 ]; then
    selected_file="${matching_files[0]}"
    #echo "One matching firmware file found: $selected_file"
else
    echo "Multiple matching firmware files found:"
    for i in "${!matching_files[@]}"; do
		selected_file="${matching_files[$i]}"
		# Extract the part before and after the last slash
		before_last_slash="${selected_file%/*}"
		before_last_slash="${before_last_slash##*/}"
		after_last_slash="${selected_file##*/}"
        echo "$((i+1)). ${before_last_slash}/${after_last_slash}"
    done
    read -r -p "Select which firmware file to use [1-${#matching_files[@]}]: " file_choice
    if ! [[ "$file_choice" =~ ^[0-9]+$ ]] || [ "$file_choice" -lt 1 ] || [ "$file_choice" -gt "${#matching_files[@]}" ]; then
        echo "Invalid selection. Exiting."
        exit 1
    fi
    selected_file="${matching_files[$((file_choice-1))]}"
	echo "Selected firmware file for operation: $selected_file"
fi

# Determine the script to run based on the operation.
if [ "$operation" = "update" ]; then
  script_to_run="$(dirname "$selected_file")/device-update.sh"
elif [ "$operation" = "install" ]; then
  script_to_run="$(dirname "$selected_file")/device-install.sh"
fi

# If the firmware file is for ESP32 (filename contains "esp32"), then modify the update script baud rate.
if echo "$selected_file" | grep -qi "esp32"; then
    if [ -f "$script_to_run" ]; then
        #echo "Modifying baud rate in $(basename "$script_to_run") for ESP32 firmware..."
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

# Determine whether to run the update script
if $RUN_UPDATE; then
    user_choice="y"
else
    # Prompt the user to run the update script or exit, defaulting to exit.
    read -r -p "Would you like to run the update script? (y/N): " user_choice
    user_choice=${user_choice:-N}
fi

if [[ "$user_choice" =~ ^[Yy]$ ]]; then
	# Determine the correct esptool command to use
	if "$PYTHON" -m esptool version >/dev/null 2>&1; then
		ESPTOOL_CMD="$PYTHON -m esptool"
	elif command -v esptool >/dev/null 2>&1; then
		ESPTOOL_CMD="esptool"
	elif command -v esptool.py >/dev/null 2>&1; then
		ESPTOOL_CMD="esptool.py"
	else
		# Check if 'pipx' is installed
		if command -v pipx &> /dev/null; then
			echo "pipx is installed."
			# Proceed with operations that require pipx
		else
			sudo apt -y install pipx
			echo "pipx is not installed."
			# Handle the absence of pipx, e.g., prompt for installation
		fi
		pipx install esptool 
		ESPTOOL_CMD="esptool.py"
	fi

	$ESPTOOL_CMD --baud 1200  chip_id

    echo "Running the update script..."
    # Execute the script with the firmware file as an argument.
    "$abs_script" -f "$abs_selected"
	exit 0
else
    exit 0
fi
