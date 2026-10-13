<#
.SYNOPSIS
    Intune detection script: detects an app by name and minimum version in the uninstall registry keys.

.DESCRIPTION
    Reads DisplayName and DisplayVersion from the 64-bit and 32-bit (WOW6432Node) uninstall keys in HKLM.
    The app is detected when DisplayName matches $AppName (wildcards allowed) and DisplayVersion is the
    same or newer than $AppVersion. An app without DisplayVersion counts as version 0.
    Set $AppVersion to "0" to detect any installed version.
    Writes "Installed" when the app is detected, nothing otherwise.

    Set $AppName and $AppVersion before uploading the script to Intune.

.EXAMPLE
    $AppName = "UiPath Studio"
    $AppVersion = "26.0.190"

    Detected when UiPath Studio version 26.0.190 or newer is installed.

.EXAMPLE
    $AppName = "UiPath Studio"
    $AppVersion = "0"

    Detected when any version of UiPath Studio is installed.

.NOTES
    Maintained by: KSKITDK
    Version      : 1.0.1

    Release notes
    1.0.1  - An app without DisplayVersion counts as version 0.
           - $AppVersion = "0" detects any installed version.
           - Known issue: the version is compared as text, so 9.10 is seen as older than 9.9 (fixed in 1.0.2).
    1.0.0  - First version: detection by DisplayName (wildcards) and minimum DisplayVersion
             in the 64-bit and 32-bit HKLM uninstall keys.

.LINK
    https://github.com/ksk-itdk/PSADT-WingetFW
#>

$ErrorActionPreference = "SilentlyContinue"

$AppName = "VCE Exam Simulator"
$AppVersion = "0"


$Apps = (Get-ChildItem HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\) | Get-ItemProperty | Select-Object DisplayName, @{Name='DisplayVersion'; Expression={if ($_.DisplayVersion) {$_.DisplayVersion} else {'0'}}}
$Apps += (Get-ChildItem HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\) | Get-ItemProperty | Select-Object DisplayName, @{Name='DisplayVersion'; Expression={if ($_.DisplayVersion) {$_.DisplayVersion} else {'0'}}}


$AppFound = $Apps | Where-Object {
($_.DisplayName -like $AppName) -and (($(if($_.DisplayVersion -eq 0){$_.DisplayVersion}else{[version]$_.DisplayVersion}) -replace '[a-zA-Z-]','') -ge $(if($AppVersion -eq 0){$AppVersion}else{[version]$AppVersion}))
}

if ($AppFound) 
{Write-Output "Installed"}
