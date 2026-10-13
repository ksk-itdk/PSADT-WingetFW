<#
.SYNOPSIS
    Intune detection script: detects an app by name and minimum version in the uninstall registry keys.

.DESCRIPTION
    Reads DisplayName and DisplayVersion from the 64-bit and 32-bit (WOW6432Node) uninstall keys in HKLM.
    The app is detected when DisplayName matches $AppName (wildcards allowed) and DisplayVersion is the
    same or newer than $AppVersion. Before the comparison every non-digit part of DisplayVersion is
    replaced by a dot, so for example "v2.3-beta" is compared as 2.3.
    An app without DisplayVersion counts as version 0. Set $AppVersion to "0" to detect any installed version.
    Writes "Installed" when the app is detected, nothing otherwise.

    Set $AppName and $AppVersion before uploading the script to Intune.

.EXAMPLE
    $AppName = "MNBSigner"
    $AppVersion = "1.0.26"

    Detected when MNBSigner version 1.0.26 or newer is installed.

.EXAMPLE
    $AppName = "MNBSigner"
    $AppVersion = "0"

    Detected when any version of MNBSigner is installed.

.NOTES
    Maintained by: KSKITDK
    Version      : 1.0.2

    Release notes
    1.0.2  - Version is compared as a version again instead of as text (9.10 is newer than 9.9).
           - Non-digit parts of DisplayVersion are replaced by dots before the comparison,
             so values like "v2.3-beta" or "1.0.26 (x64)" can be compared.
           - $Apps is cleared before the registry is read.
    1.0.1  - An app without DisplayVersion counts as version 0.
           - $AppVersion = "0" detects any installed version.
           - Known issue: the version is compared as text, so 9.10 is seen as older than 9.9 (fixed in 1.0.2).
    1.0.0  - First version: detection by DisplayName (wildcards) and minimum DisplayVersion
             in the 64-bit and 32-bit HKLM uninstall keys.

.LINK
    https://github.com/ksk-itdk/PSADT-WingetFW
#>

$ErrorActionPreference = "SilentlyContinue"

$AppName = "MNBSigner"
$AppVersion = "1.0.26"
$Apps = $null


$Apps = (Get-ChildItem HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\) | Get-ItemProperty | Select-Object DisplayName, @{Name='DisplayVersion'; Expression={if ($_.DisplayVersion) {$_.DisplayVersion} else {'0'}}}
$Apps += (Get-ChildItem HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\) | Get-ItemProperty | Select-Object DisplayName, @{Name='DisplayVersion'; Expression={if ($_.DisplayVersion) {$_.DisplayVersion} else {'0'}}}

$AppFound = @()
foreach ($App in $Apps) {
    $displayVersion = ($App.DisplayVersion -replace '[^\d]+', '.' -replace '^\.+|\.+$', '')
    $cleanVersion = if ($displayVersion -eq 0) { $displayVersion } else { [version]$displayVersion }
    $targetVersion = if ($AppVersion -eq 0) { $AppVersion } else { [version]$AppVersion }
    
    if (($App.DisplayName -like $AppName) -and ($cleanVersion -ge $targetVersion)) {
        $AppFound += $App
    }
}

if ($AppFound) 
{Write-Output "Installed"}
