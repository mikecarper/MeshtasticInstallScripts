#!/bin/bash

# Copy this file to firmware from the https://github.com/meshtastic/firmware/ repo

# Optionally pass the desired environment name as the first argument.
env_arg="$1"

# Get environment names from platformio.ini files.
# This finds all lines that start with [env: and then strips off the prefix and trailing ].
mapfile -t envs < <(
    find . -type f -name "platformio.ini" -exec grep -h "^\[env:" {} \; \
    | sort -u \
    | sed -n 's/^\[env:\([^]]*\)].*/\1/p'
)

# Check if any environments were found.
if [ ${#envs[@]} -eq 0 ]; then
    echo "No environments found in platformio.ini files."
    exit 1
fi

selected_env=""

if [ -n "$env_arg" ]; then
    # Try to auto-select an environment that matches the provided argument (case-insensitive).
    for env in "${envs[@]}"; do
        if [[ "${env,,}" == "${env_arg,,}" ]]; then
            selected_env="$env"
            break
        fi
    done

    if [ -z "$selected_env" ]; then
        echo "Environment '$env_arg' not found in the list."
    else
        echo "Auto-selected environment: $selected_env"
    fi
fi

if [ -z "$selected_env" ]; then
    # Display a numbered menu for the user to choose an environment.
    echo "Select an environment:"
    for i in "${!envs[@]}"; do
        printf "%d) %s\n" $((i+1)) "${envs[$i]}"
    done

    read -rp "Enter number: " selection
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#envs[@]} ]; then
        echo "Invalid selection."
        exit 1
    fi

    selected_env="${envs[$((selection-1))]}"
    echo "You selected: $selected_env"
fi

# Now you have the selected environment in $selected_env.
# You can use it further in your script.
echo "Final environment: $selected_env"
if [ -z "$env_arg" ]; then
    read -rp "Press Enter to continue..."
fi

output=$(git pull --recurse-submodules 2>&1)
status=$?

if [ $status -ne 0 ] && echo "$output" | grep -q "Your local changes to the following files would be overwritten by merge"; then
    git reset --hard
    git pull --recurse-submodules
    git apply extra.patch
    
    # Iterate over all platformio.ini files in ~/firmware and its subdirectories.
    find . -type f -name "platformio.ini" | while read -r file; do
        # Check if the file contains the string (using -- to treat the pattern literally)
        if grep -q -- "-DMESHTASTIC_EXCLUDE_REMOTEHARDWARE=1" "$file"; then
            echo "Processing: $file"
            # Replace the string in-place
            sed -i 's/-DMESHTASTIC_EXCLUDE_REMOTEHARDWARE=1/-DMESHTASTIC_EXCLUDE_REMOTEHARDWARE=0/g' "$file"
        fi
    done

    echo "All platformio.ini files have been updated."

else
    echo "$output"
fi

platformio pkg update -e "$selected_env"

VERSION=$(bin/buildinfo.py long)

# The shell vars the build tool expects to find
export APP_VERSION=$VERSION

OUTDIR=release/$VERSION/

rm -f "${OUTDIR:?}"/firmware*
rm -r "${OUTDIR:?}"/* || true
mkdir -p "$OUTDIR"

echo "Building for $selected_env with $PLATFORMIO_BUILD_FLAGS"
rm -f .pio/build/"$selected_env"/firmware.*


basename=firmware-$selected_env-$VERSION

pio run --environment "$selected_env" # -v
SRCELF=.pio/build/"$selected_env"/firmware.elf
cp "$SRCELF" "$OUTDIR"/"$basename".elf

echo "Copying ESP32 bin file"
SRCBIN=.pio/build/"$selected_env"/firmware.factory.bin
cp "$SRCBIN" "$OUTDIR"/"$basename".bin

echo "Copying ESP32 update bin file"
SRCBIN=.pio/build/"$selected_env"/firmware.bin
cp "$SRCBIN" "$OUTDIR"/"$basename"-update.bin

echo "Building Filesystem for ESP32 targets"
pio run --environment "$selected_env" -t buildfs
cp .pio/build/"$selected_env"/littlefs.bin "$OUTDIR"/littlefswebui-"$selected_env"-"$VERSION".bin
# Remove webserver files from the filesystem and rebuild
ls -l data/static # Diagnostic list of files
rm -rf data/static
pio run --environment "$selected_env" -t buildfs
cp .pio/build/"$selected_env"/littlefs.bin "$OUTDIR"/littlefs-"$selected_env"-"$VERSION".bin
cp bin/device-install.* "$OUTDIR"
cp bin/device-update.* "$OUTDIR"

rm "$OUTDIR"/"$basename".elf

find "$OUTDIR" -maxdepth 1 -type f -exec du -h {} \; \
  | sed 's|^\./||' \
  | awk '{print $1, $2}' \
  | column -t

if [ -f ~/.vpnServerInfo ]; then
    # Read the connection info (expected format: user@ip) from ~/.vpnServerInfo.
    connection=$(<~/.vpnServerInfo)
    # Now proceed with the SCP command.
    scp -r "$OUTDIR"/* "${connection}":"~/meshfirmware/meshtastic_firmware/compiled"
fi
