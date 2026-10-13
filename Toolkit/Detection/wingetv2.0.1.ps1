<#
.SYNOPSIS
    Intune detection script: detects an app with winget list, as SYSTEM or as the user.

.DESCRIPTION
    Runs "winget list --id $app --exact" and writes "Installed" when the output contains $app.
    Writes nothing when the app is not installed or winget is not found.

    Admin/SYSTEM (Intune install behavior System): winget.exe from C:\Program Files\WindowsApps,
    App Installer 1.2x first, otherwise the last folder found.
    User (Intune install behavior User): winget.exe from %LOCALAPPDATA%\Microsoft\WindowsApps.

    Set $app to the winget package ID (or Microsoft Store ID) before uploading the script to Intune.

.EXAMPLE
    $app = "argoproj.argocd"

    Detected when Argo CD CLI is installed.

.NOTES
    Maintained by: KSKITDK
    Version      : 2.0.1

    Release notes
    2.0.1  - winget is started with System.Diagnostics.Process and its output is read from the redirected
             standard output; running winget with & failed in some cases.
    2.0.0  - Works in user context: without admin rights winget.exe is taken from %LOCALAPPDATA%\Microsoft\WindowsApps.
    1.0.0  - First version: detection with winget list --id --exact, run as SYSTEM.

.LINK
    https://github.com/ksk-itdk/PSADT-WingetFW
#>

$ErrorActionPreference = "SilentlyContinue"

$app = "SUSE.RancherDesktop"

## Variables: Permissions/Accounts
[Security.Principal.WindowsIdentity]$CurrentProcessToken = [Security.Principal.WindowsIdentity]::GetCurrent()
[Boolean]$IsAdmin = [Boolean]($CurrentProcessToken.Groups -contains [Security.Principal.SecurityIdentifier]'S-1-5-32-544')

If($IsAdmin){
    $winget = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_1.2*_x64__8wekyb3d8bbwe\winget.exe"
    if($winget -EQ $null){
        $winget = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
    }
}
If(-Not $IsAdmin){
    $winget = Resolve-Path "$env:LOCALAPPDATA\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller*\winget.exe"
    if($winget -EQ $null){
        $winget = Resolve-Path "$env:LOCALAPPDATA\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe"
    }
}

if ($winget.count -gt 1){
        $winget = $winget[-1].Path
}

if (!$winget){
    Write-Error "Winget not installed"
}else{
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $winget
    $processInfo.Arguments = "list --id $app --exact --accept-source-agreements"
    $processInfo.RedirectStandardOutput = $true
    $processInfo.UseShellExecute = $false

    $process = [System.Diagnostics.Process]::Start($processInfo)
    $wingetPrg = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()

    if ($wingetPrg -like "*$app*"){
        Write-Output "Installed"
    }
}

