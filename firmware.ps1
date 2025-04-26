# 2>NUL & @powershell -nop -ep bypass "(gc '%~f0')-join[Environment]::NewLine|iex" && @EXIT /B 0

#Example execute:
# powershell -ExecutionPolicy ByPass -File c:\bin\meshtastic\firmware.ps1


# Register a Ctrl-C handler:
$null = Register-ObjectEvent -InputObject ([System.Console]) `
    -EventName CancelKeyPress -Action {
        # $EventArgs is in scope here:
        $EventArgs.Cancel = $true
        Write-Host "`nCaught Ctrl-C." -ForegroundColor Yellow
		Read-Host "Press Enter to exit (via Ctrl-C)"
    }

# Function to fetch the latest stable Python version from GitHub
function Get-LatestPythonVersion {
    $url = "https://api.github.com/repos/actions/python-versions/releases/latest"
    $release = Invoke-RestMethod -Uri $url -Headers @{Accept = "application/vnd.github.v3+json"}
    $latestVersion = $release.tag_name
    return $latestVersion
}

# Check if Python is installed
$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
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
        $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
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






# Get all Serial Ports and filter for USB serial devices by checking Description and DeviceID
$comDevices = Get-WmiObject Win32_SerialPort

# Now filter based on Description containing "USB" and DeviceID starting with "COM"
$usbComDevices = $comDevices | Where-Object {
    # Explicitly check for USB and COM conditions
    Write-Host "Checking device: $($_.DeviceID) - $($_.Description) - $($_.PNPDeviceID)"
    $_.Description -like "*USB*" -and $_.DeviceID -like "*COM*"
}

# Check if the filtered USB COM devices collection is not empty
if ($usbComDevices) {
    # Loop through each USB COM device and run the meshtastic command
    foreach ($device in $usbComDevices) {
        $selectedComPort = $device.DeviceID

        # Run meshtastic command on the current COM port and capture both stdout and stderr
        Write-Host "Running meshtastic command on port $selectedComPort"
        $meshtasticOutput = & meshtastic --device-metadata --port $selectedComPort 2>&1

        # Debugging: print the raw meshtastic output for each port
        #Write-Host "Raw meshtastic output for $selectedComPort"
        #Write-Host $meshtasticOutput

        # Adjusted regex to capture the firmware version correctly
        $versionRegex = 'firmware_version:\s*([^\s]+)'  # Capture the version number after "firmware_version:"

        # Use Select-String to find all matches
        $matches = $meshtasticOutput | Select-String -Pattern $versionRegex -AllMatches

        # Check if there are matches and display them
        if ($matches) {
            $matches.Matches | % { Write-Host "Firmware version for $selectedComPort - $($_.Value)" }
        } else {
            Write-Host "Firmware version not found for $selectedComPort."
        }
    }
} else {
    Write-Host "No USB COM devices found."
    $comDevices | Select-Object DeviceID, Description, PNPDeviceID | Format-Table
    exit
}







   
# When the user finally hits Enter, the script will exit naturally.
Read-Host "Press Enter to exit (via end of script)"
