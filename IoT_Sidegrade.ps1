if (!(New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error -Message "Script needs to be run with administrator privileges. Aborting." -ErrorAction Stop
}

function Restore-RegistryValues {
    <#
    .SYNOPSIS
    Function used as a failsafe. Retrievs what the original registry values were and reverts the changes, leaving the registry virtually untouched.
    .PARAMETER regValues
    Takes the variable that is set during the very beginning of the script execution. This contains all the original registry values.
    .PARAMETER retVal
    Takes the return value variable, that is used in this script to output exit codes, representing the status of the finished script execution
    #>
    param(
        [Parameter(Mandatory = $True, Position = 0)]
        $regValues,
        [Parameter(Mandatory = $True, Position = 1)]
        [int]$retVal
    )

    try {
        Set-ItemProperty -Path "Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "EditionID" -Value $regValues.EditionID
        Set-ItemProperty -Path "Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "ProductName" -Value $regValues.ProductName
    }
    catch {
        Write-Output "An additional error occured while trying to restore the registry."
        Write-Output "Key HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\EditionID should be reset to $($regValues.EditionID)"
        Write-Output "Key HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProductName should be reset to $($regValues.ProductName)"

        Write-Error $Error -ErrorAction Ignore
        return -1
    }

    Write-Output "Registry keys successfully restored."
    return 0
}

$retVal = [int]0
$currentVersion = Get-ItemProperty -Path "Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\"

try {
    #region Set Registry Values
    Write-Output "Settings registry keys..."
    try {
        Set-ItemProperty -Path "Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "EditionID" -Value "IoTEnterpriseS"
        Set-ItemProperty -Path "Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "ProductName" -Value "Windows 10 IoT Enterprise LTSC 2021"
    }
    catch {
        Write-Output "Registry keys couldn't be written due to an error."
        Write-Error -Message $Error
        return -10
    }

    Write-Output "Registry keys successfully written"
    #endregion

    #region Locate ISO
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
    $fileSelectionDlg = New-Object System.Windows.Forms.OpenFileDialog # Generating the dialog that let's the user select an ISO
    $fileSelectionDlg.Filter = "ISO Files (*.iso)|*.iso"
    $fileSelectionDlg.Title  = "Select Windows 10 IoT Enterprise LTSC 2021 ISO file..."
    $dlgResult = $fileSelectionDlg.ShowDialog() # Opening the dialog

    if ($dlgResult -eq "OK") { # Handler for when a file was selected
        $imagePath = $fileSelectionDlg.FileName
        Write-Output "Selected ISO file: $($imagePath)"
    }
    else { # Handler for when no file was selected (pressed Cancel, closed the window, etc.)
        Write-Output "No ISO file was selected. Aborting."
        $retVal -= 2
        exit
    }
    #endregion

    #region Mount ISO
    if ($(Get-DiskImage -ImagePath $imagePath).Attached -eq $False) {
        try {
            Write-Output "Mounting ISO..."
            $mountDisk = Mount-DiskImage -ImagePath $imagePath -PassThru
            while ($(Get-DiskImage -ImagePath $imagePath).Attached -eq $False) { # Wait for the ISO to be mounted before continuing with the script
                Start-Sleep -Milliseconds 250
            }
            $mountVol = ($mountDisk | Get-Volume).DriveLetter # Save the mounted ISO's drive letter
        }
        catch {
            Write-Output "Mounting the ISO file failed, reverting registry changes..."
            Write-Error -Message $Error
            return -20 + $(Restore-RegistryValues $currentVersion $retVal)
        }
    }
    else { # Handler for when an ISO was selected, but the selected file is already mounted
        Write-Output "ISO already mounted, locating drive letter..."
        $mountVol = ($(Get-DiskImage -ImagePath $imagePath) | Get-Volume).DriveLetter
    }

    Write-Output "Drive letter of mounted ISO: $($mountVol):"
    #endregion

    #region Get WIM index of IoTEnterpriseS image
    Write-Output "Searching install medium for right index of the IoT Enterprise LTSC installer..."
    $imagePath = "$($mountVol):\sources\install.wim"

    if (Test-Path $imagePath) { # Makes sure that an "install.wim" file is located inside the ISO
        $installWim = Get-WindowsImage -ImagePath $imagePath
    }
    else {
        Write-Output "The install medium either contains the installatin images in an unsupported format (only WIM images are supported, ESD images don't work with this script) or the selected ISO does not contain a Windows installer. Aborting."
        $retVal -= 20
        exit
    }

    for ($i = 0; $i -lt $installWim.Count; $i++) { # Loop that locates the index of Windows 10 IoT Enterprise LTSC on "install.wim"
        if ($installWim[$i].ImageName -eq "Windows 10 IoT Enterprise LTSC") {
            $imageIndex = $i + 1 # Adding 1, because WIM indexes start with 1 instead of 0
        }
    }

    if ($null -eq $imageIndex) { # For when an "install.wim" exists but only contains other OSes than the one we're trying to install
        Write-Output "The selected Windows installation ISO does not contain an installation for Windows 10 IoT Enterprise LTSC. Aborting."
        exit
    }

    Write-Output "Found index on install medium: $($imageIndex)"
    $noErrorOccured = $True # Tells the logic inside the finally block that no errors occured during above processes
    #endregion
}
finally {
    if ($noErrorOccured) {
        #region Start setup
        Write-Host "Starting the Windows setup wizard..."
        Start-Process -FilePath "$($mountVol):\setup.exe" -ArgumentList "/DiagnosticPrompt enable", "/DynamicUpdate disable", "/EULA accept", "/ImageIndex $($imageIndex)", "/Telemetry disable", "/Uninstall enable" -Wait # The arguments are explained in the README.md of the repository
        exit
        #endregion
    }

    # Error handeling for process breaking errors
    Write-Host "Exiting script, reverting registry changes..."
    $retVal += Restore-RegistryValues $currentVersion $retVal

    if ($null -ne $mountVol) {
        Write-Host "Disk image is still mounted. Dismounting..."
        Dismount-DiskImage -ImagePath $imagePath | Out-Null
        Write-Host "Dismount of image file was successfull."
    }
}

return $retVal