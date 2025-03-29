#!/bin/bash

# Iterate over all platformio.ini files in ~/firmware and its subdirectories.
find ~/firmware -type f -name "platformio.ini" | while read -r file; do
    # Check if the file contains the string (using -- to treat the pattern literally)
    if grep -q -- "-DMESHTASTIC_EXCLUDE_REMOTEHARDWARE=1" "$file"; then
        echo "Processing: $file"
        # Replace the string in-place
        sed -i 's/-DMESHTASTIC_EXCLUDE_REMOTEHARDWARE=1/-DMESHTASTIC_EXCLUDE_REMOTEHARDWARE=0/g' "$file"
    fi
done

echo "All platformio.ini files have been updated."
