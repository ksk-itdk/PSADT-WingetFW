$ErrorActionPreference = "SilentlyContinue"

$app = "SUSE.RancherDesktop"

## Variables: Permissions/Accounts
[Security.Principal.WindowsIdentity]$CurrentProcessToken = [Security.Principal.WindowsIdentity]::GetCurrent()
[Boolean]$IsAdmin = [Boolean]($CurrentProcessToken.Groups -contains [Security.Principal.SecurityIdentifier]'S-1-5-32-544')

If($IsAdmin){
    $winget = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_1.21*_x64__8wekyb3d8bbwe\winget.exe"
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

