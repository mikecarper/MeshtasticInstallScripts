# 2>NUL & @powershell -nop -ep bypass "(gc '%~f0')-join[Environment]::NewLine|iex" && @EXIT /B 0

#Example execute:
# powershell -ExecutionPolicy ByPass -File c:\git\MeshtasticInstallScripts\firmware.ps1


# Flag to track if Ctrl-C has been pressed
$scriptOver = $false

# Register a Ctrl-C handler:
$null = Register-ObjectEvent -InputObject ([System.Console]) `
    -EventName CancelKeyPress -Action {
        # $EventArgs is in scope here:
        $EventArgs.Cancel = $true
        
        if (-not $scriptOver) {
            # First Ctrl-C press: prompt user
            Write-Host "`nCaught Ctrl-C." -ForegroundColor Yellow
            $scriptOver = $true
            Read-Host "Press Enter to exit (via Ctrl-C)"
        } else {
            # Second Ctrl-C press: exit without prompt
            Write-Host "`nExiting script..." -ForegroundColor Red
            exit
        }
    }

$ScriptPath = $PSScriptRoot
if ([string]::IsNullOrEmpty($ScriptPath)) {
    $ScriptPath = (Get-Location).Path
}

$timeoutMeshtastic = 10 # Timeout duration in seconds
$baud = 1200 # 115200
$downloadUrl = "https://www.nirsoft.net/utils/usbdeview-x64.zip"
$usbDeviewPath = Join-Path -Path $ScriptPath -ChildPath "USBDeview.exe"
$zipFilePath = Join-Path -Path $ScriptPath -ChildPath "usbdeview-x64.zip"
$extractFolderPath = Join-Path -Path $ScriptPath -ChildPath "USBDeview"


$CACHE_TIMEOUT_SECONDS=6 * 3600 # 6 hours


        $GITHUB_API_URL="https://api.github.com/repos/meshtastic/firmware/releases"
          $REPO_API_URL="https://api.github.com/repos/meshtastic/meshtastic.github.io/contents"
 $WEB_HARDWARE_LIST_URL="https://raw.githubusercontent.com/meshtastic/web-flasher/refs/heads/main/public/data/hardware-list.json"
 
         $FIRMWARE_ROOT="${ScriptPath}/meshtastic_firmware"
          $DOWNLOAD_DIR="${ScriptPath}/meshtastic_firmware/downloads"

         $RELEASES_FILE="${ScriptPath}/meshtastic_firmware/releases.json"
         $HARDWARE_LIST="${ScriptPath}/meshtastic_firmware/hardware-list.json"
    $VERSIONS_TAGS_FILE="${ScriptPath}/meshtastic_firmware/01versions_tags.txt"
  $VERSIONS_LABELS_FILE="${ScriptPath}/meshtastic_firmware/02versions_labels.txt"
       $CHOSEN_TAG_FILE="${ScriptPath}/meshtastic_firmware/03chosen_tag.txt"
 $DOWNLOAD_PATTERN_FILE="${ScriptPath}/meshtastic_firmware/04download_pattern.txt"
 
 
     $ARCHITECTURE_FILE="${ScriptPath}/meshtastic_firmware/11architecture.txt"


# Function to fetch the latest stable Python version from GitHub
function Get-LatestPythonVersion {
    $url = "https://api.github.com/repos/actions/python-versions/releases/latest"
    $release = Invoke-RestMethod -Uri $url -Headers @{Accept = "application/vnd.github.v3+json"}
    $latestVersion = $release.tag_name
    return $latestVersion
}

function get_esptool_cmd() {
	try {
		# Check if Python is installed and get the version
		$pythonVersion = & $pythonCommand --version
		Write-Progress -Status "Checking Versions" -Activity "Python interpreter found: $pythonVersion"
		# Set the ESPTOOL command to use Python
		$ESPTOOL_CMD = "$pythonCommand -m esptool"  # Construct as a single string
	} catch {
		# If Python is not found, check for esptool in the system PATH
		Write-Host "Python interpreter not found. Checking for esptool..."

		$esptoolPath = Get-Command esptool -ErrorAction SilentlyContinue

		if ($esptoolPath) {
			# If esptool is found, set the ESPTOOL command
			$ESPTOOL_CMD = "esptool"  # Set esptool command
		} else {
			# If neither Python nor esptool is found, fallback to python -m esptool
			Write-Host "esptool not found. Falling back to python -m esptool."
			$ESPTOOL_CMD = "python -m esptool"  # Fallback to Python esptool
		}
	}
	
	$run = run_esptool_cmd "$ESPTOOL_CMD version"
	$esptoolVersion = $run | Select-Object -Last 1
	if ($pythonVersion) {
		Write-Progress -Status "Checking Versions" -Activity "Python interpreter found: $pythonVersion esptool version: $esptoolVersion"
	}
	else {
		Write-Progress -Status "Checking Versions" -Activity "esptool version: $esptoolVersion"
	}

	
	return $ESPTOOL_CMD
}

function run_esptool_cmd($ESPTOOL_CMD) {
    # Create two temporary files for capturing standard output and error
    $tempOutputFile = Join-Path -Path $ScriptPath -ChildPath "esptool_output.txt"
    $tempErrorFile = Join-Path -Path $ScriptPath -ChildPath "esptool_error.txt"

    # Ensure we split the command and arguments properly into an array
    $commandParts = $ESPTOOL_CMD.Split(" ")

    # Start the process and capture both standard output and error to separate files
    Start-Process -FilePath $commandParts[0] -ArgumentList $commandParts[1..$commandParts.Length] -PassThru -Wait -NoNewWindow -RedirectStandardOutput $tempOutputFile -RedirectStandardError $tempErrorFile | out-null

    # Get the content of both the output and error files
    $content = Get-Content $tempOutputFile

    # Clean up the temporary files
    Remove-Item $tempOutputFile -Force
    Remove-Item $tempErrorFile -Force

    # Return only the filtered content
    return $content
}

function check_requirements() {
	# Check if Python is installed
	$global:pythonCommand = Get-Command python -ErrorAction SilentlyContinue
	if (-not $pythonCommand) {
		# Get the latest stable Python version
		$latestPythonVersion = Get-LatestPythonVersion
		Write-Host "Python is not installed."

		# Ask the user if they want to install Python
		$installPython = Read-Host "Do you want to install Python $latestPythonVersion now? (Y/N)"
		if ($installPython -eq 'Y' -or $installPython -eq 'y') {
			Write-Host "Downloading and installing Python $latestPythonVersion..."

			# Set Python installer URL for Windows
			$pythonInstallerUrl = "https://www.python.org/ftp/python/$latestPythonVersion/python-$latestPythonVersion-amd64.exe"
			$installerPath = "$env:TEMP\python_installer.exe"

			# Download the Python installer
			Invoke-WebRequest -Uri $pythonInstallerUrl -OutFile $installerPath

			# Run the installer silently with 'Add Python to PATH' option enabled
			Start-Process -FilePath $installerPath -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait

			# Clean up the installer
			Remove-Item $installerPath

			Write-Host "Python $latestPythonVersion has been installed successfully."

			# Recheck if Python is installed
			$global:pythonCommand = Get-Command python -ErrorAction SilentlyContinue
			if (-not $pythonCommand) {
				Write-Host "Python installation failed. Please check your system."
				exit
			}
		} else {
			Write-Host "Please install Python manually and run the script again."
			exit
		}
	}

	# Check if meshtastic is installed
	$meshtasticCommand = Get-Command meshtastic -ErrorAction SilentlyContinue
	if (-not $meshtasticCommand) {
		Write-Host "Meshtastic is not installed. Installing..."

		# Check if pip3 is installed
		$pip3Command = Get-Command pip3 -ErrorAction SilentlyContinue
		if (-not $pip3Command) {
			Write-Host "pip3 is not installed. Installing pip3..."
			# Download the get-pip.py script
			$getPipUrl = "https://bootstrap.pypa.io/get-pip.py"
			$getPipScriptPath = "$env:TEMP\get-pip.py"
			Invoke-WebRequest -Uri $getPipUrl -OutFile $getPipScriptPath

			# Run the script to install pip3
			python $getPipScriptPath

			# Clean up the get-pip.py script
			Remove-Item $getPipScriptPath
		}

		# Install or upgrade meshtastic using pip3
		pip3 install --upgrade "meshtastic[cli]"
		Write-Host "Meshtastic installed/updated successfully."
	}
}




function getallUSBCom($output) {
	# Get all Serial Ports and filter for USB serial devices by checking Description and DeviceID
	#$comDevices = Get-WmiObject Win32_SerialPort
	$comDevices = Get-WmiObject -Class Win32_PnPEntity | Where-Object { $_.DeviceID -like "*USB*" -and $_.Name -like "*(com*" }
	
	# Initialize the array for storing the results
	$usbComDevices = @()

	foreach ($device in $comDevices) {
		#$device
		# Extract COM port from the Name property
		if ($device.Name -match 'COM(\d+)') {
			$comPort = $matches[0]  # The full COM port string like COM3 or COM5
		}

		# Split the string by "\" and get the last part
		$HardwareID = $device.HardwareID.Split("\")[-1]

		# Add the device information to $usbComDevices
		$usbComDevices += [PSCustomObject]@{
			drive_letter      = $comPort
			device_name       = $HardwareID
			friendly_name     = $device.Name
			firmware_revision = "--"
		}
	}

	return $usbComDevices
}

function getMeshtasticNodeInfo($selectedComPort) {
	# Define a temporary file to capture the output
	$tempOutputFile = Join-Path -Path $ScriptPath -ChildPath "meshtastic_output$selectedComPort.txt"
	$tempErrorFile = Join-Path -Path $ScriptPath -ChildPath "meshtastic_error$selectedComPort.txt"

	# Start the meshtastic process with a hidden window and capture the process ID
	#Write-Host "Running meshtastic command on port $selectedComPort"
	$process = Start-Process "meshtastic" -ArgumentList "--port $selectedComPort --info --no-nodes" -PassThru -WindowStyle Hidden -RedirectStandardOutput $tempOutputFile -RedirectStandardError $tempErrorFile
	$processWait = $process.WaitForExit($timeoutMeshtastic * 1000)  # Timeout is in milliseconds
	
	
	$meshtasticOutput = ""
	# Check if the process exited within the timeout
	if ($processWait) {
		# If the process exits within the timeout, capture the output
		$meshtasticOutput = Get-Content $tempOutputFile -Raw
		$meshtasticError = Get-Content $tempErrorFile -Raw
	} else {
		# If the process did not exit within the timeout, forcefully kill it
		return "Timed Out"
		$process.Kill()
	}
	
	# Dispose the process object to release resources
	$process.Dispose()
	
	# Ensure the process has fully exited and file handles are released before cleanup
	Start-Sleep -Seconds 1

	# Clean up: remove temporary files
	try {
		Remove-Item $tempOutputFile -Force | out-null
		Remove-Item $tempErrorFile -Force | out-null
	} catch {
		Write-Warning "ERROR: Could not delete temporary files. Make sure no other process is using them."
	}

	$meshtasticOutput = $meshtasticOutput -replace '(\{|\}|\,)', "$1`n"

	$deviceInfo = New-Object PSObject -property @{
		Name        = ""
		HWName      = ""
		HWNameShort = ""
		FWVersion   = ""
	}

	$splitted = $meshtasticOutput -split "`n"
	$splitted | ForEach-Object {
		# Split each line into key-value pairs
		$i = $_ -split ":", 2
		if ($i.Count -eq 2) {
			# Ensure that the line contains both key and value
			$key = $i[0].Trim() -replace '"', ""
			$value = $i[1].Trim() 

			# Matching keys and storing values
			if ($key -like "*Owner*") {
				$deviceInfo.Name = $value
			}
			if ($key -like "*pioEnv*") {
				$deviceInfo.HWName = $value -replace '"', ""  # Removing any quotes in the value
			}
			if ($key -like "*hwModel*") {
				$deviceInfo.HWNameShort = $value -replace '"', ""  # Removing any quotes in the value
			}
			if ($key -like "*firmwareVersion*") {
				$deviceInfo.FWVersion = $value -replace '"', ""  # Removing any quotes in the value
			}
		}
	}
	
	if ($meshtasticError) {
		Write-Host "Error"
		Write-Host $meshtasticError
	}

	return $deviceInfo
}

function selectUSBCom() {
    param (
        [Parameter(Mandatory=$true)]
        $availableComPorts
    )
	# Display a menu with available COM ports
	$validPort = $false
	while (-not $validPort) {
		# Ask the user to enter the COM port to operate on
		$selectedComPort = Read-Host "Enter the COM port to operate on"

		# Normalize the input to ensure both 'COM7' and '7' are valid
		if ($selectedComPort -match '^\d+$') {
			# If it's just a number, prepend "COM" to it
			$selectedComPort = "COM$selectedComPort"
		}

		# Check if the selected COM port exists in the list of USB COM devices
		if ($availableComPorts -contains $selectedComPort) {
			Write-Host "Selected COM port is valid: $selectedComPort"
			# Proceed with further operations on the selected COM port
			$validPort = $true
		} else {
			Write-Host "Invalid COM port: $selectedComPort  Please select a valid COM port."
		}
	}


    return $selectedComPort
}

function USBDeview() {

	if (-not (Test-Path $usbDeviewPath)) {
		Write-Host "USBDeview.exe not found. Downloading and extracting..."

		# Download the zip file
		Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFilePath

		# Extract the zip file
		Expand-Archive -Path $zipFilePath -DestinationPath $extractFolderPath -Force

		# Check if the extraction was successful and move the exe to the desired location
		$extractedExePath = Join-Path -Path $extractFolderPath -ChildPath "USBDeview.exe"

		if (Test-Path $extractedExePath) {
			# Move the USBDeview.exe to the ScriptPath
			Move-Item -Path $extractedExePath -Destination $usbDeviewPath -Force
			Write-Host "USBDeview.exe extracted and moved successfully."
		} else {
			Write-Host "ERROR: Failed to extract USBDeview.exe."
		}

		# Clean up: Remove the downloaded zip file and extracted folder
		Remove-Item -Path $zipFilePath -Force
		Remove-Item -Path $extractFolderPath -Recurse -Force
	}

	# Define a path for the usb_devices.xml file
	$usbDevicesOutputPath = Join-Path -Path $ScriptPath -ChildPath "usb_devices.xml"
	if (Test-Path $usbDevicesOutputPath) {
		Remove-Item -Path $usbDevicesOutputPath -Force
	}

	# Run USBDeview and output the connected devices in XML format
	Write-Progress -Status "Getting USB Devices" -Activity "Running $ScriptPath\USBDeview.exe /sort DriveLetter /TrayIcon 0 /DisplayDisconnected 0 /sxml $usbDevicesOutputPath"
	$usbDevices = Start-Process -FilePath "$ScriptPath\USBDeview.exe" -ArgumentList "/sort DriveLetter /TrayIcon 0 /DisplayDisconnected 0 /sxml $usbDevicesOutputPath" -PassThru -Wait -NoNewWindow

	# Check if the XML output file exists
	if (Test-Path $usbDevicesOutputPath) {
		# Load the XML file
		[xml]$xmlContent = Get-Content -Path $usbDevicesOutputPath

		# Extract and display device information (e.g., drive letter, description, etc.)
		$usbDevicesList = $xmlContent.usb_devices_list.item

		# Filter out devices with drive letters starting with 'COM' and display relevant details
		$comDevices = $usbDevicesList | Where-Object { $_.drive_letter -like "COM*" }
		
		return $comDevices
	} else {
		Write-Host "Error: usb_devices.xml not found. USBDeview was not ran successfully."
		exit
	}
}

# Function to get and display the USB devices
function getUsbComDevices() {
	$usbComDevices = @()
    #$comDevices = USBDeview  
	$comDevices = getallUSBCom

    # Process each device and store the relevant details in $usbComDevices
    $comDevices | ForEach-Object {
		Write-Progress -Status "Checking USB Devices" -Activity "Checking for meshtastic on $($_.drive_letter)"
		$deviceInfo = getMeshtasticNodeInfo $_.drive_letter
		if ($deviceInfo -eq "Timed Out") {
			$usbComDevices += [PSCustomObject]@{
				COMPort           = $_.drive_letter
				DeviceName        = $_.device_name
				FriendlyName      = $_.friendly_name
				FirmwareVersion   = $_.firmware_revision
				Meshtastic 	      = $deviceInfo
			} 
		}
        else {
			$usbComDevices += [PSCustomObject]@{
				ComPort           = $_.drive_letter
				DeviceName        = $deviceInfo.HWName
				FriendlyName      = $deviceInfo.Name
				FirmwareVersion   = $deviceInfo.FWVersion
				Meshtastic	 	  = $deviceInfo.HWNameShort
			} 
		}
    }
	return $usbComDevices
}

function getUSBComPort() {
	$selectedComPort = 0 
	# Run in a loop until we get valid $comDevices
	do {
		$usbComDevices = getUsbComDevices

		# If there are no USB COM devices, display an error and loop again
		if ($usbComDevices.Count -eq 0) {
			Write-Host "No valid COM devices found. Please check the connection." -ForegroundColor Red
			Start-Sleep -Seconds 5  # Wait before trying again
		} else {
			$availableComPorts = $usbComDevices | Select-Object -ExpandProperty ComPort
			if ($availableComPorts.Count -eq 1) {
				$meshtasticVersion = $usbComDevices | Select-Object -ExpandProperty FirmwareVersion
				$hwModelSlug = $usbComDevices | Select-Object -ExpandProperty Meshtastic
				$selectedComPort = "$availableComPorts"
				#Write-Host "$selectedComPort. Version: $meshtasticVersion. Hardware: $hwModelSlug."
			}
			else {
				# If we found valid COM devices, let the user select one
				$tableOutput = $usbComDevices | Sort-Object -Property ComPort | Format-Table -Property ComPort, DeviceName, FriendlyName, FirmwareVersion, Meshtastic | Out-String
				# Remove lines that are empty or only contain spaces
				$tableOutput = $tableOutput -split "`n" | Where-Object { $_.Trim() -ne "" } | Out-String
				
				Write-Host ""
				Write-Host $tableOutput
				$selectedComPort = selectUSBCom -availableComPorts $availableComPorts
				
				# now filter out the single object whose ComPort matches
				$device = $usbComDevices |
					Where-Object { $_.ComPort -eq $selectedComPort }

				# and pull out the fields you care about
				$hwModelSlug       = $device.Meshtastic
				$meshtasticVersion = $device.FirmwareVersion

				#Write-Host "$selectedComPort. Version: $meshtasticVersion. Hardware: $hwModelSlug."
				
			}
		}

	} while ($usbComDevices.Count -eq 0 -and $selectedComPort -eq 0)  # Continue looping until we have at least one valid COM device
	return ,$selectedComPort, $hwModelSlug
}






# Check for an active internet connection.
function CheckInternet {
    $domain = [uri]$GITHUB_API_URL
    $domain = $domain.Host
    try {
        # Ping the domain to check for internet connection.
        if (Test-Connection -ComputerName $domain -Count 1 -Quiet) {
            return $true
        } else {
            return $false
        }
    } catch {
        return $false
    }
}

# Update the GitHub release cache if needed.
function UpdateReleases {
    if (-not (CheckInternet)) {
		Write-Progress -Activity "No internet connection; using cached release data if available."
		Return
	}
	if ((Test-Path $RELEASES_FILE) -and (Get-Date).AddSeconds(-$CACHE_TIMEOUT_SECONDS) -lt (Get-Item $RELEASES_FILE).LastWriteTime) {
		Write-Progress -Activity "Using cached release data (up to date within the last 6 hours)."
		return
	}
	
	# Create the firmware directory if it doesn't exist
	if (-not (Test-Path $FIRMWARE_ROOT)) {
		New-Item -ItemType Directory -Path $FIRMWARE_ROOT | Out-Null
	}

	# Ensure the directory for $RELEASES_FILE exists
	$releasesDir = [System.IO.Path]::GetDirectoryName($RELEASES_FILE)
	if (-not (Test-Path $releasesDir)) {
		New-Item -ItemType Directory -Path $releasesDir | Out-Null
	}

	Write-Progress -Activity "Updating release cache from GitHub..."
	# Download into a temp file first
	$tmpFile = [System.IO.Path]::GetTempFileName()
	try {
		Invoke-WebRequest -Uri $GITHUB_API_URL -OutFile $tmpFile -ErrorAction Stop
	} catch {
		Write-Host "Failed to download release data."
		Remove-Item $tmpFile
		return
	}

	# Check if the downloaded file is valid JSON
	try {
		$jsonContent = Get-Content $tmpFile | ConvertFrom-Json
	} catch {
		Write-Host "Downloaded file is not valid JSON. Aborting."
		Remove-Item $tmpFile
		return
	}

	# Filter out "download_count" keys from the JSON.
	$filteredTmp = [System.IO.Path]::GetTempFileName()
	$jsonContent | ConvertTo-Json -Depth 10 | ForEach-Object { 
		$_ -replace '"download_count":\s*\d+,', ''
	} | Set-Content -Path $filteredTmp

	# Use the filtered JSON for further processing.
	if (-not (Test-Path $RELEASES_FILE)) {
		Move-Item $filteredTmp $RELEASES_FILE
		Remove-Item $tmpFile
	} else {
		# Compare the MD5 hashes of the cached file and the newly filtered file.
		$oldMd5 = Get-FileHash $RELEASES_FILE -Algorithm MD5
		$newMd5 = Get-FileHash $filteredTmp -Algorithm MD5
		if ($oldMd5.Hash -ne $newMd5.Hash) {
			Write-Progress -Activity "Release data changed. Updating cache and removing cached version lists. $($oldMd5.Hash) $($newMd5.Hash)"
			Remove-Item $RELEASES_FILE
			Move-Item $filteredTmp $RELEASES_FILE
			Remove-Item $VERSIONS_TAGS_FILE, $VERSIONS_LABELS_FILE | Out-Null
		} else {
			Write-Progress -Activity "Release data is unchanged. $($oldMd5.Hash) $($newMd5.Hash)"
			
			# Update the LastWriteTime of the RELEASES_FILE to the current time
			Set-ItemProperty -Path $RELEASES_FILE -Name LastWriteTime -Value (Get-Date)
			
			Remove-Item $filteredTmp
		}
		Remove-Item $tmpFile
	}
}

function UpdateHardwareList {    
    # Check if the file exists and if it's older than 6 hours
    if (-not (Test-Path $HARDWARE_LIST) -or ((Get-Date) - (Get-Item $HARDWARE_LIST).LastWriteTime).TotalMinutes -gt 360) {
        Write-Progress -Activity "Downloading resources.ts from GitHub..."
        
        # Create the directory if it doesn't exist
        $directory = [System.IO.Path]::GetDirectoryName($HARDWARE_LIST)
        if (-not (Test-Path $directory)) {
            New-Item -Path $directory -ItemType Directory
        }

        # Download the file
        Invoke-WebRequest -Uri $WEB_HARDWARE_LIST_URL -OutFile $HARDWARE_LIST
    }
}



# Function to build the release menu and save version tags and labels.
function BuildReleaseMenuData {
    $tmpfile = New-TemporaryFile

    $ReleasesJson = Get-Content -Path "$RELEASES_FILE" -Raw
    $ReleasesJson = $ReleasesJson -replace '[^\x00-\x7F]', '' # Remove non-ASCII characters.

    # Parse the JSON manually
    $jsonData = $ReleasesJson | ConvertFrom-Json

    # Loop through each release to build the entries.
    foreach ($release in $jsonData) {
        $tag = $release.tag_name
        $prerelease = $release.prerelease
        $draft = $release.draft
        $body = $release.body
        $created_at = $release.created_at

        $suffix = ""
        $date = $created_at

        if ($tag -match "[Aa]lpha") {
            $suffix = "$suffix (alpha)"
        } elseif ($tag -match "[Bb]eta") {
            $suffix = "$suffix (beta)"
        } elseif ($tag -match "[Rr][Cc]") {
            $suffix = "$suffix (rc)"
        }

        if ($draft -eq $true) {
            $suffix = "$suffix (draft)"
        } elseif ($prerelease -eq $true) {
            $suffix = "$suffix (pre-release)"
        }

        $tag = $tag.Substring(1)  # Remove the 'v' from the version tag
        $label = "{0,-14} {1}" -f $tag, $suffix

        if ($body -match '⚠️') {
            $label = "! $label"
        } elseif ($body -match 'Known issue') {
			$label = "! $label"
		} elseif ($body -match 'Revocation') {
			$label = "! $label"
		}
		else {
            $label = "  $label"
        }

        # Write the entry to the temporary file.
        "$date`t$tag`t$label" | Out-File -Append -FilePath $tmpfile
    }

    # Check if any subdirectory name in FIRMWARE_ROOT (skip "downloads") is not in the tag_names from above.
    Get-ChildItem -Path $FIRMWARE_ROOT | ForEach-Object {
        $folder = $_
        if ($folder.PSIsContainer -and $folder.Name -ne "downloads") {
            $folderName = $folder.Name.ToLower()

            if ($folderName -match "^v") {
                $folderName = $folderName.Substring(1)
            }

            $found = $false
            $content = Get-Content -Path $tmpfile
            foreach ($line in $content) {
                if ($line -match $folderName) {
                    $found = $true
                    break
                }
            }

            if (-not $found) {
                $firstFile = Get-ChildItem -Path $folder.FullName -File -Filter "firmware-*" | Select-Object -First 1
                if ($firstFile) {
                    $mtime = (Get-Date (Get-Item $firstFile.FullName).LastWriteTime -UFormat "%Y-%m-%dT%H:%M:%SZ")
                } else {
                    $mtime = (Get-Date (Get-Item $folder.FullName).LastWriteTime -UFormat "%Y-%m-%dT%H:%M:%SZ")
                }

                $label = "! $folderName $mtime (nightly)"
                "$mtime`t$folderName`t$label" | Out-File -Append -FilePath $tmpfile
            }
        }
    }

    # Sort all entries by date in descending order (newest first)
    $sortedEntries = Get-Content -Path $tmpfile | Sort-Object -Descending

    # Build arrays from the sorted entries.
    $versionsTags = @()
    $versionsLabels = @()

    foreach ($entry in $sortedEntries) {
        $fields = $entry -split "`t"
        $versionsTags += $fields[1]
        $versionsLabels += $fields[2]
    }

    # Save the arrays for later use.
    $versionsTags | Out-File -FilePath $VERSIONS_TAGS_FILE
    $versionsLabels | Out-File -FilePath $VERSIONS_LABELS_FILE
    Write-Host ""
}




function SelectRelease {
    param([string] $VersionArg)
	
	Write-Progress -Activity " " -Status " " -Completed

    # load the cached lists
    $versionsTags   = Get-Content $VERSIONS_TAGS_FILE
    $versionsLabels = Get-Content $VERSIONS_LABELS_FILE
    $count          = $versionsLabels.Count
    if ($count -eq 0) { throw "No releases cached." }

    # find first stable index
    $latestStableIndex = 0
    for ($i = 0; $i -lt $count; $i++) {
        if ($versionsLabels[$i] -notlike '! *' -and $versionsLabels[$i] -notlike '* (pre-release)*') {
            $latestStableIndex = $i
            break
        }
    }

    if ($VersionArg) {
        $chosen = $versionsTags.FindIndex({ $_ -like "*$VersionArg*" })
        if ($chosen -lt 0) { throw "No matching release for '$VersionArg'" }
    }
    else {
        # layout maths
        $termWidth      = $Host.UI.RawUI.WindowSize.Width
        $maxLabelLength = ($versionsLabels | Measure-Object Length -Maximum).Maximum
        $indexWidth     = $count.ToString().Length
        $colLabelWidth  = $maxLabelLength + 2
        $colWidth       = $indexWidth + 2 + $colLabelWidth + 8
        $numPerRow      = [Math]::Max(1, [int]($termWidth / $colWidth))

        # 1) BUILD the array of PSCustomObject{text, color}
        $formatted = for ($i = 0; $i -lt $count; $i++) {
            $label = $versionsLabels[$i]
            $text  = "{0:D$indexWidth}) {1,-$colLabelWidth}" -f ($i+1), $label

            # pick a color
            if ($label -match '[Nn]ightly') {
                $color = 'Red'
            }
            elseif ($i -eq $latestStableIndex) {
                $color = 'Cyan'
            }
            elseif ($label -match '\(pre-release\)' -and -not $script:PreColored) {
                $script:PreColored = $true
                $color = 'Yellow'
            }
            elseif ($label -notmatch '\(pre-release\)' -and -not $script:StableColored) {
                $script:StableColored = $true
                $color = 'Green'
            }
            else {
                $color = 'White'
            }

            [PSCustomObject]@{ Text = $text; Color = $color }
        }

        # 2) reverse in-place so oldest → newest
        [Array]::Reverse($formatted)

        # 3) print in rows
        $row = 0
        foreach ($item in $formatted) {
            Write-Host -NoNewline $item.Text -ForegroundColor $item.Color
            $row++
            if ($row % $numPerRow -eq 0) { Write-Host }
        }
        if ($row % $numPerRow -ne 0) { Write-Host }

        # 4) prompt
        do {
            $sel = Read-Host -Prompt "Enter number of your selection (1-$count)"
        } until ($sel -as [int] -and $sel -ge 1 -and $sel -le $count)
        $chosen = $sel - 1
    }

    # save & return
    $tag = $versionsTags[$chosen]
    $tag | Out-File -Encoding ascii -NoNewline $CHOSEN_TAG_FILE
    return $tag
}




function DownloadAssets {
    <#
    .SYNOPSIS
      Download all firmware-* assets for the chosen release (skipping any “debug” builds).
    #>

    # 1) Read & parse the cached release JSON
    $jsonRaw = Get-Content -Path $RELEASES_FILE -Raw
    $jsonRaw = $jsonRaw -replace '[^\x00-\x7F]', ''
    try {
        $allReleases = $jsonRaw | ConvertFrom-Json
    } catch {
        Throw "Failed to parse JSON from '$RELEASES_FILE': $_"
    }

    # 2) Determine the chosen tag
    $chosenTag = (Get-Content -Path $CHOSEN_TAG_FILE -Raw).Trim()
    if (-not $chosenTag) {
        Throw "No chosen tag found in '$CHOSEN_TAG_FILE'."
    }
    $downloadPattern = "-$chosenTag"

    # 3) Find the release object
    $release = $allReleases |
        Where-Object { $_.tag_name.TrimStart('v') -eq $chosenTag } |
        Select-Object -First 1
    if (-not $release) {
        Throw "Release with tag '$chosenTag' not found."
    }

    # 4) Filter its assets
    $assets = $release.assets |
        Where-Object { $_.name -match '^firmware-' -and $_.name -notmatch 'debug' }
    if (-not $assets) {
        Throw "No firmware assets found for release '$chosenTag'."
    }

    # 5) Prepare download dir & remove stale temps
    if (-not (Test-Path $DOWNLOAD_DIR)) {
        New-Item -Path $DOWNLOAD_DIR -ItemType Directory | Out-Null
    }
    Get-ChildItem -Path $DOWNLOAD_DIR -Filter '*.tmp*' -File |
        Remove-Item -Force

    # 6) Download loop
    $hadExisting = $false
    foreach ($asset in $assets) {
        $name = $asset.name
        $url  = $asset.browser_download_url
        $dest = Join-Path $DOWNLOAD_DIR $name

        if (Test-Path $dest) {
			Write-Progress -Activity "Already have $name"
            $hadExisting = $true
            continue
        }

        if ($hadExisting) { Write-Host ""; $hadExisting = $false }

        $tmpFile = Join-Path $DOWNLOAD_DIR ("{0}.tmp" -f ([Guid]::NewGuid()))
        try {
            Invoke-WebRequest -Uri $url -OutFile $tmpFile -UseBasicParsing -ErrorAction Stop
            Move-Item -Path $tmpFile -Destination $dest -Force
        } catch {
            Write-Host "  ✗ Failed to download $name" -ForegroundColor Red
            Remove-Item -Path $tmpFile -ErrorAction SilentlyContinue
        }
    }

    # 7) Save the pattern marker
    Set-Content -Path $DOWNLOAD_PATTERN_FILE -Value $downloadPattern
	Write-Progress -Activity " " -Status " " -Completed
}



function UnzipAssets {
    param(
        [string] $ReleasesFile  = $RELEASES_FILE,
        [string] $ChosenTagFile = $CHOSEN_TAG_FILE,
        [string] $DownloadDir   = $DOWNLOAD_DIR,
        [string] $FirmwareRoot  = $FIRMWARE_ROOT
    )

    # 1) Read chosen tag
    $chosenTag = (Get-Content -Path $ChosenTagFile -Raw).Trim()
    if (-not $chosenTag) {
        Throw "No chosen tag found in '$ChosenTagFile'."
    }

    # 2) Load & parse all releases
    $jsonRaw = Get-Content -Path $ReleasesFile -Raw
    $jsonRaw = $jsonRaw -replace '[^\x00-\x7F]', ''
    try {
        $allReleases = $jsonRaw | ConvertFrom-Json
    } catch {
        Throw "Failed to parse JSON from '$ReleasesFile': $_"
    }

    # 3) Locate the release object by tag (strip leading 'v')
    $release = $allReleases |
        Where-Object { $_.tag_name.TrimStart('v') -eq $chosenTag } |
        Select-Object -First 1
    if (-not $release) {
        Throw "Release '$chosenTag' not found in JSON."
    }

    # 4) Filter for firmware-… zip assets (exclude debug)
    $assets = $release.assets |
        Where-Object { 
            $_.name -match '^firmware-' -and 
            $_.name -notmatch 'debug'
        }
    if (-not $assets) {
        Throw "No matching firmware assets found for release '$chosenTag'."
    }

    # 5) Unzip each asset to <FirmwareRoot>\<tag>\<product>\…
    foreach ($asset in $assets) {
        $name      = $asset.name
        $localFile = Join-Path $DownloadDir $name

        if ($name -match '^firmware-([^-\s]+)-.+\.zip$') {
            $product   = $Matches[1]
            $targetDir = Join-Path $FirmwareRoot "$chosenTag\$product"

            # ensure folder exists
            New-Item -Path $targetDir -ItemType Directory -Force | Out-Null

            # if empty, unzip
            $hasFiles = Get-ChildItem -Path $targetDir -File -Recurse -ErrorAction SilentlyContinue
            if (-not $hasFiles) {
                Expand-Archive -Path $localFile -DestinationPath $targetDir -Force
            }
            else {
				Write-Progress -Activity "Skipping $name - target folder already populated."
            }
        }
        else {
            Write-Host "Asset '$name' does not match expected naming convention; skipping."
        }
    }
		Write-Progress -Activity " " -Status " " -Completed
} 






function GetHardwareInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Slug,

        [Parameter(Mandatory)]
        [string] $ListPath
    )

    if (-not (Test-Path $ListPath)) {
        Throw "Hardware list not found at path: $ListPath"
    }

    # Load & parse JSON
    $hardwareList = Get-Content -Path $ListPath -Raw | ConvertFrom-Json

    # Find matching entry
    $entry = $hardwareList |
        Where-Object { $_.hwModelSlug -eq $Slug } |
        Select-Object -First 1

    if (-not $entry) {
        Throw "No hardware entry found for slug '$Slug'"
    }

    # Determine if those optional properties actually exist, otherwise default to $false
    $requiresDfu = if ($entry.PSObject.Properties.Name -contains 'requiresDfu') { $entry.requiresDfu } else { $false }
    $hasInkHud   = if ($entry.PSObject.Properties.Name -contains 'hasInkHud')   { $entry.hasInkHud   } else { $false }
    $hasMui      = if ($entry.PSObject.Properties.Name -contains 'hasMui')      { $entry.hasMui      } else { $false }

    # Build and return a PSCustomObject
    return [PSCustomObject]@{
        Slug         = $entry.hwModelSlug
        Architecture = $entry.architecture
        DisplayName  = $entry.displayName
        RequiresDfu  = $requiresDfu
        HasInkHud    = $hasInkHud
		HasMui       = $hasMui
    }
}



function MakeConfigBackup {
	[CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $HWNameShort,

        [Parameter(Mandatory)]
        $selectedComPort
    )
	
	Write-Host "Making a config backup"

	# Generate the backup config name
	$backupConfigName = "$ScriptPath\config_backup.${HWNameShort}.${selectedComPort}.$([System.DateTime]::Now.ToString('yyyyMMddHHmmss')).yaml"

	# Start the loop for backup process
	while ($true) {
		try {
			# Run the meshtastic command and redirect output to the backup config file
			Write-Host "Running meshtastic --port $selectedComPort --export-config > $backupConfigName"
			# Start the Meshtastic process and redirect both stdout and stderr to the backup config file
			$process = Start-Process -FilePath "meshtastic" -ArgumentList "--port $selectedComPort --export-config" -PassThru -Wait -NoNewWindow -RedirectStandardOutput "$backupConfigName" -RedirectStandardError "$backupConfigName.error"

			# Check if the file has been created and output the file size
			if (Test-Path "$backupConfigName") {
				$fileSize = (Get-Item "$backupConfigName").Length
				if ("$fileSize" -gt 0) {
					if (-not (Test-Path "$backupConfigName.error") -or ((Get-Item "$backupConfigName.error").length -eq 0)) {
						Write-Host "Backup configuration created: $backupConfigName. $fileSize bytes"
						if (Test-Path "$backupConfigName.error") {
							Remove-Item "$backupConfigName.error" -Force | out-null
						}
						break
					}
					else {
						$content = Get-Content "$backupConfigName.error" -Raw
						Write-Host "Error from meshtastic:"
						Write-Host $content
					}
				}
			}
			Write-Host "Failed to create backup configuration."
			$response = Read-Host "Press Enter to try again or type 'skip' to skip the creation"
			if ($response -eq "skip") {
				Write-Host "Skipping config backup."
				break
			}
			Start-Sleep -Seconds 1
		} catch {
			# If there's an error, print the warning message
			Write-Host "Error caught: $($_.Exception.Message)"
			Write-Host "Warning: Timed out waiting for connection completion. Config backup not done." -ForegroundColor Red

			# Prompt the user for input to either try again or skip
			$response = Read-Host "Press Enter to try again or type 'skip' to skip the creation"

			if ($response -eq "skip") {
				Write-Host "Skipping config backup."
				break
			}
			
			# Wait for 1 second before retrying
			Start-Sleep -Seconds 1
		}
	}
	
}





# Get release info
check_requirements
UpdateReleases
BuildReleaseMenuData
$tag = SelectRelease
DownloadAssets
UnzipAssets

# Get node info
UpdateHardwareList
$ESPTOOL_CMD = get_esptool_cmd
$result = getUSBComPort
$selectedComPort = $result[0]
$HWNameShort    = $result[1]

$hw = GetHardwareInfo -Slug $HWNameShort -ListPath $HARDWARE_LIST
Write-Host "Selected hardware:    $($hw.DisplayName)"
Write-Host "  Architecture:       $($hw.Architecture)"
Write-Host "  Requires DFU?:      $($hw.RequiresDfu)"
Write-Host "  Has Ink HUD?:       $($hw.HasInkHud)"
Write-Host "  Has Meshtastic UI?: $($hw.HasMui)"

MakeConfigBackup $HWNameShort $selectedComPort



Read-Host "Press Enter to put node into Device Firmware Update (DFU) mode"
Write-Host "Running $ESPTOOL_CMD --baud $baud --port $selectedComPort chip_id"
$output = run_esptool_cmd "$ESPTOOL_CMD --baud $baud --port $selectedComPort chip_id"
Write-Host $output


   
# When the user finally hits Enter, the script will exit naturally.
$scriptOver = $true
Read-Host 'Press Enter to exit (via end of script)'
