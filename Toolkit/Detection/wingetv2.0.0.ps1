$ErrorActionPreference = "SilentlyContinue"

$app = "Ditto.Ditto"

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
    $wingetPrg = & $winget list --id $app --exact --accept-source-agreements
        if ($wingetPrg -like "*$app*"){
        Write-Output "Installed"
    }
}

