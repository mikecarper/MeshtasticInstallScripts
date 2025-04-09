#!/bin/bash


VPN_INFO="$HOME/.vpnServerInfo"
# Number of attempts for each file
MAX_ATTEMPTS=60
# Timeout in seconds for scp (adjust if needed)
SCP_TIMEOUT=5

# Optionally pass the desired environment name as the first argument.
env_arg="$1"

# Update git
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


platformio pkg update -e "$selected_env"

VERSION=$(bin/buildinfo.py long)
VERSION="${VERSION::-3}777"

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

if [ -f .pio/build/"$selected_env"/firmware.factory.bin ]; then
    echo "Copying ESP32 bin file"
    SRCBIN=.pio/build/"$selected_env"/firmware.factory.bin
    cp "$SRCBIN" "$OUTDIR"/"$basename".bin
fi

if [ -f .pio/build/"$selected_env"/firmware.bin ]; then
    echo "Copying ESP32 update bin file"
    SRCBIN=.pio/build/"$selected_env"/firmware.bin
    cp "$SRCBIN" "$OUTDIR"/"$basename"-update.bin
fi

if [ -f .pio/build/"$selected_env"/firmware.zip ]; then
    echo "Generating NRF52 dfu file"
    DFUPKG=.pio/build/"$selected_env"/firmware.zip
    cp $DFUPKG $OUTDIR/$basename-ota.zip
fi

if [ -f .pio/build/"$selected_env"/firmware.hex ]; then
    echo "Generating NRF52 uf2 file"
    SRCHEX=.pio/build/"$selected_env"/firmware.hex
fi

if [ ! -z "$SRCHEX" ]; then
	bin/uf2conv.py $SRCHEX -c -o $OUTDIR/$basename.uf2 -f 0xADA52840
	cp bin/*.uf2 $OUTDIR
else
    echo "Building Filesystem for ESP32 targets"
    pio run --environment "$selected_env" -t buildfs
    cp .pio/build/"$selected_env"/littlefs.bin "$OUTDIR"/littlefswebui-"$selected_env"-"$VERSION".bin
    # Remove webserver files from the filesystem and rebuild
    ls -l data/static # Diagnostic list of files
    rm -rf data/static
    pio run --environment "$selected_env" -t buildfs
    cp .pio/build/"$selected_env"/littlefs.bin "$OUTDIR"/littlefs-"$selected_env"-"$VERSION".bin
fi
cp bin/device-install.* "$OUTDIR"
cp bin/device-update.* "$OUTDIR"

rm "$OUTDIR"/"$basename".elf

find "$OUTDIR" -maxdepth 1 -type f -exec du -h {} \; \
  | sed 's|^\./||' \
  | awk '{print $1, $2}' \
  | column -t

if [ -f $VPN_INFO ]; then
    # Trap SIGINT (Ctrl-C) to kill all child processes and exit.
    trap 'echo "Interrupted by Ctrl-C. Exiting."; kill 0; exit 1' SIGINT

    # Loop through each non-empty, non-comment line in the VPN info file.
    while IFS= read -r connection || [ -n "$connection" ]; do
        echo ""
        echo $connection
        # Skip empty lines or lines beginning with '#' (comments)
        [[ -z "$connection" || "$connection" =~ ^# ]] && continue

        # Prompt for the password once.

        read -rp "Enter password for SCP/SSH: " PASSWORD < /dev/tty

        if [ "$PASSWORD" != "skip" ]; then
            for file in "$OUTDIR"/*; do
                [ -f "$file" ] || continue
                basefile=$(basename "$file")
                # Compute the local MD5 checksum.
                local_md5=$(md5sum "$file" | awk '{print $1}')
                attempt=1
                success=0

                while [ $attempt -le $MAX_ATTEMPTS ]; do
                    echo -n "$attempt: $basefile -> $connection..."
                    printf "\r"

                    # Ensure the remote directory exists.
                    sshpass -p "$PASSWORD" ssh -n -o StrictHostKeyChecking=no "$connection" "mkdir -p ~/meshfirmware/meshtastic_firmware/${VERSION}/"

                    # Use timeout with --foreground so that Ctrl-C is delivered to the child process.
                    timeout --foreground $SCP_TIMEOUT sshpass -p "$PASSWORD" scp -r -o StrictHostKeyChecking=no "$file" "${connection}:~/meshfirmware/meshtastic_firmware/${VERSION}/" < /dev/null
                    scp_status=$?

                    if [ $scp_status -ne 0 ]; then
                        #echo "scp failed (exit status $scp_status) for $basefile on $connection. Retrying..."
                        attempt=$((attempt+1))
                        continue
                    fi

                    # Compute the remote MD5 checksum via ssh.
                    remote_md5=$(sshpass -p "$PASSWORD" ssh -n -o StrictHostKeyChecking=no "$connection" "md5sum ~/meshfirmware/meshtastic_firmware/${VERSION}/${basefile} 2>/dev/null" | awk '{print $1}')


                    if [ "$local_md5" = "$remote_md5" ]; then
                        echo "$basefile copied to $connection (MD5 matched)."
                        success=1
                        break
                    else
                        echo "MD5 mismatch for $basefile on $connection. Retrying..."
                        attempt=$((attempt+1))
                    fi
                done

                if [ $success -ne 1 ]; then
                    echo "Failed to copy $basefile to $connection after $MAX_ATTEMPTS attempts."
                fi
            done

            echo "Finished processing $connection."
        fi
    done < "$VPN_INFO"
fi
