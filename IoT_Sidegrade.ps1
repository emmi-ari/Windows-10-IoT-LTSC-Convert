#Requires -RunAsAdministrator

function Restore-RegistryValues {
    param(
        [Parameter(Mandatory = $True, Position = 0)]
        $regValues,
        [Parameter(Mandatory = $True, Position = 1)]
        [int]$retVal,
        [Parameter(Mandatory = $False, Position = 2)]
        [bool]$exitOnError
    )

    try {
        Set-ItemProperty -Path "Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "EditionID" -Value $regValues.EditionID
        Set-ItemProperty -Path "Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "ProductName" -Value $regValues.ProductName
    }
    catch {
        Write-Output "An additional error occured while trying to restore the registry."
        Write-Output "Key HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\EditionID should be reset to $($regValues.EditionID)"
        Write-Output "Key HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProductName should be reset to $($regValues.ProductName)"
        if ($null -eq $exitOnError) {
            Write-Error $Error -ErrorAction Ignore
        }
        else {
            Write-Error $Error -ErrorAction Stop
        }
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
    $fileSelectionDlg = New-Object System.Windows.Forms.OpenFileDialog
    $fileSelectionDlg.Filter = "ISO Files (*.iso)|*.iso"
    $fileSelectionDlg.Title  = "Select Windows 10 IoT Enterprise LTSC 2021 ISO file..."
    $dlgResult = $fileSelectionDlg.ShowDialog()
    if ($dlgResult -eq "OK") {
        $imagePath = $fileSelectionDlg.FileName
        Write-Output "Selected ISO file: $($imagePath)"
    }
    else {
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
            $mountVol = ($mountDisk | Get-Volume).DriveLetter
        }
        catch {
            Write-Output "Mounting the ISO file failed, reverting registry changes..."
            Write-Error -Message $Error
            return -20 + $(Restore-RegistryValues $currentVersion $retVal)
        }
    }
    else {
        Write-Output "ISO already mounted, locating drive letter..."
        $mountVol = ($(Get-DiskImage -ImagePath $imagePath) | Get-Volume).DriveLetter
    }

    Write-Output "Drive letter of mounted ISO: $($mountVol):"
    #endregion

    #region Get WIM index of IoTEnterpriseS image
    Write-Output "Searching install medium for right index of the IoT Enterprise LTSC installer..."
    $installWim = Get-WindowsImage -ImagePath "$($mountVol):\sources\install.wim" # TODO Add case handeling if it's not a wim image
    for ($i = 0; $i -lt $installWim.Count; $i++) {
        if ($installWim[$i].ImageName -eq "Windows 10 IoT Enterprise LTSC") {
            $imageIndex = $i + 1 # Adding 1, because WIM indexes start with 1 instead of 0
        }
    }

    if ($null -eq $imageIndex) {
        Write-Output "The selected Windows installation ISO does not contain an installation for Windows 10 IoT Enterprise LTSC. Aborting."
        exit
    }

    Write-Output "Found index on install medium: $($imageIndex)"
    $noErrorOccured = $True
    #endregion
}
finally {
    if ($noErrorOccured) {
        #region Start setup
        Write-Host "Starting the Windows setup wizard..."
        Start-Process -FilePath "$($mountVol):\setup.exe" -ArgumentList "/DiagnosticPrompt enable", "/DynamicUpdate disable", "/EULA accept", "/ImageIndex $($imageIndex)", "/Telemetry disable", "/Uninstall enable" -Wait
        exit
        #endregion
    }
    Write-Host "Exiting script, reverting registry changes..."
    $retVal += Restore-RegistryValues $currentVersion $retVal $True
    if ($null -ne $mountVol) {
        Dismount-DiskImage -ImagePath $imagePath | Out-Null
    }
}

return $retVal