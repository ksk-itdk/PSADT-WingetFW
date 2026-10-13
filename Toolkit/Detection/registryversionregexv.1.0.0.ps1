<#
.SYNOPSIS
    Intune detection script: detects an app by name and minimum version in the uninstall registry keys.

.DESCRIPTION
    Reads DisplayName and DisplayVersion from the 64-bit and 32-bit (WOW6432Node) uninstall keys in HKLM.
    The app is detected when DisplayName matches $AppName (wildcards allowed) and DisplayVersion,
    with letters and '-' removed, is the same or newer than $AppVersion.
    Writes "Installed" when the app is detected, nothing otherwise.

    Set $AppName and $AppVersion before uploading the script to Intune.

.EXAMPLE
    $AppName = "LINQPad 9*"
    $AppVersion = "9.5.10"

    Detected when LINQPad 9 version 9.5.10 or newer is installed.

.NOTES
    Maintained by: KSKITDK
    Version      : 1.0.0

    Release notes
    1.0.0  - First version: detection by DisplayName (wildcards) and minimum DisplayVersion
             in the 64-bit and 32-bit HKLM uninstall keys.

.LINK
    https://github.com/ksk-itdk/PSADT-WingetFW
#>

$ErrorActionPreference = "SilentlyContinue"

$AppName = "NVM for Windows*"
$AppVersion = "1.2.2" 


$Apps = (Get-ChildItem HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\) | Get-ItemProperty | select DisplayName, DisplayVersion
$Apps += (Get-ChildItem HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\) | Get-ItemProperty | select DisplayName, DisplayVersion


$AppFound = $Apps | Where-Object {
($_.DisplayName -like $AppName) -and ([version]($_.DisplayVersion -replace '[a-zA-Z-]','') -ge [version]$AppVersion)
}

if ($AppFound) 
{Write-Output "Installed"}
