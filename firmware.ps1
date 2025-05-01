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
	$comDevices = Get-WmiObject -Class Win32_PnPEntity | Where-Object { $_.DeviceID -like "*USB*" -and $_.Description -like "*serial*" -and $_.Name -like "*com*" }

	# Now filter based on Description containing "USB" and DeviceID starting with "COM"
	if ($output -ne 0) {
		foreach ($device in $comDevices) {
			Write-Host "Found com device: $($device.DeviceID) - $($device.Description) - $($device.Name)"
		}
	}
	return $comDevices
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
		Write-Host "Error: usb_devices.xml not found. Ensure USBDeview ran successfully."
		exit
	}
}

# Function to get and display the USB devices
function getUsbComDevices() {
	$usbComDevices = @()
    # Run USBDeview command (modify this to capture actual output from USBDeview)
    $comDevices = USBDeview  # Replace this with your actual command to fetch USB devices

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
				$meshtasticVersion = $usbComDevices | Select-Object -ExpandProperty FWVersion
				$selectedComPort = "$availableComPorts"
				Write-Host "Only one COM port found, automatically selecting: $selectedComPort Version: $meshtasticVersion"
			}
			else {
				# If we found valid COM devices, let the user select one
				$tableOutput = $usbComDevices | Sort-Object -Property ComPort | Format-Table -Property ComPort, DeviceName, FriendlyName, FirmwareVersion, Meshtastic | Out-String
				# Remove lines that are empty or only contain spaces
				$tableOutput = $tableOutput -split "`n" | Where-Object { $_.Trim() -ne "" } | Out-String
				
				Write-Host ""
				Write-Host $tableOutput
				$selectedComPort = selectUSBCom -availableComPorts $availableComPorts
			}
		}

	} while ($usbComDevices.Count -eq 0 -and $selectedComPort -eq 0)  # Continue looping until we have at least one valid COM device
	return $selectedComPort
}




check_requirements
$ESPTOOL_CMD = get_esptool_cmd
$selectedComPort = getUSBComPort

Write-Host "Making a config backup"

# Generate the backup config name
$backupConfigName = "$ScriptPath\config_backup.${selectedComPort}.$([System.DateTime]::Now.ToString('yyyyMMddHHmmss')).yaml"

# Start the loop for backup process
while ($true) {
    try {
        # Run the meshtastic command and redirect output to the backup config file
		Write-Host "Running meshtastic --port $selectedComPort --export-config"
        # Start the Meshtastic process and redirect both stdout and stderr to the backup config file
		$process = Start-Process -FilePath "meshtastic" -ArgumentList "--port $selectedComPort --export-config" -PassThru -Wait -NoNewWindow -RedirectStandardOutput "$backupConfigName" -RedirectStandardError "$backupConfigName.error"

		# Check if the file has been created and output the file size
		if (Test-Path "$backupConfigName") {
			$fileSize = (Get-Item "$backupConfigName").Length
			if ("$fileSize" -gt 0) {
				if (-not (Test-Path "$backupConfigName.error") -or ((Get-Item "$backupConfigName.error").length -eq 0)) {
					Write-Host "Backup configuration created: $backupConfigName. $fileSize bytes"
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


Read-Host "Press Enter to put node into Device Firmware Update (DFU) mode"
Write-Host "Running $ESPTOOL_CMD --baud $baud --port $selectedComPort chip_id"
$output = run_esptool_cmd "$ESPTOOL_CMD --baud $baud --port $selectedComPort chip_id"
Write-Host $output


   
# When the user finally hits Enter, the script will exit naturally.
$scriptOver = $true
Read-Host "Press Enter to exit (via end of script)"
