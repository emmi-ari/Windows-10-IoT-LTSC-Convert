# Windows-10-IoT-LTSC-Convert
Script to automate sidegrading any Windows 10 install to Windows 10 IoT LTSC

## Requirements
- Admin rights
- Windows 10 IoT Enterprise LTSC 2021 ISO

## What does this script do exactly
The script sets the registry keys that reflect the current Windows 10 Version that is installed. This is done in order to tell the installer, that the currently installed version of Windows is already the IoT Enterprise LTSC version. If this wouldn't be done, upgrading, whilst keeping programs and settings wouldn't be possible.
After the values are written to the registry, the script let's you select the right ISO file, which will then be analyzed by the script, to automate the OS selection part of the installation wizard.
The ISO gets mounted and `setup.exe` is started with following parameters:
```
/DiagnosticPrompt - Makes cmd.exe available to use while the setup runs (using Shift + F10)
/DynamicUpdate    - Disables downloading updates before starting the installation
/EULA             - Automatically accepts the license agreement
/ImageIndex       - Selects the right Windows image to install (gets determined during the analysis step of the script)
/Telemetry        - Disables telemetry while using the setup wizard
/Uninstall        - Enables the option to revert to the old Windows version after the upgrade
```

## Running the script
1. To run this script you have to open a PowerShell window with administrative privileges, by opening the start menu, searching for `powershell.exe` and clicking "Run as administrator", or pressing Ctrl + Shift + Enter
2. After opening an admin PowerShell window, paste this command and press enter:
```pwsh
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process; Invoke-WebRequest 'https://raw.githubusercontent.com/emmi-ari/Windows-10-IoT-LTSC-Convert/refs/heads/main/IoT_Sidegrade.ps1' | Invoke-Expression```
