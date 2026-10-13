<#
.SYNOPSIS
    Intune detection script: detects an app with winget list, as SYSTEM or as the user.

.DESCRIPTION
    Runs "winget list --id $app --exact" and writes "Installed" when the output contains $app.
    Writes nothing when the app is not installed.

    Admin/SYSTEM (Intune install behavior System): the newest winget.exe in C:\Program Files\WindowsApps.
    User (Intune install behavior User): winget.exe from %LOCALAPPDATA%\Microsoft\WindowsApps. Right after a
    user's first logon Windows registers winget a few seconds late, so the registration is requested and
    the script waits up to 20 seconds.

    When winget is not found or fails, the reason is written to the error output and the script exits
    with code 1, so it shows in the Intune Management Extension log. Intune treats this as not detected.

    Set $app to the winget package ID (or Microsoft Store ID) before uploading the script to Intune.

.EXAMPLE
    $app = "argoproj.argocd"

    Detected when Argo CD CLI is installed.

.NOTES
    Maintained by: KSKITDK
    Version      : 2.0.2

    Release notes
    2.0.2  - Admin/SYSTEM: the newest App Installer folder is used (sorted by version, not as text and
             not only 1.2x), so App Installer 1.100 and later are found.
           - User: when winget is not found, the App Installer registration is requested and winget is
             looked for again for up to 20 seconds (first logon race).
           - winget exit code is checked: "no installed package found" means not installed; other errors
             are retried twice and then written to the error output with exit code 1.
           - winget is stopped after 120 seconds.
    2.0.1  - winget is started with System.Diagnostics.Process and its output is read from the redirected
             standard output; running winget with & failed in some cases.
    2.0.0  - Works in user context: without admin rights winget.exe is taken from %LOCALAPPDATA%\Microsoft\WindowsApps.
    1.0.0  - First version: detection with winget list --id --exact, run as SYSTEM.

.LINK
    https://github.com/ksk-itdk/PSADT-WingetFW
#>

$ErrorActionPreference = "SilentlyContinue"

$app = "argoproj.argocd"

## Variables: Permissions/Accounts
[Security.Principal.WindowsIdentity]$CurrentProcessToken = [Security.Principal.WindowsIdentity]::GetCurrent()
[Boolean]$IsAdmin = [Boolean]($CurrentProcessToken.Groups -contains [Security.Principal.SecurityIdentifier]'S-1-5-32-544')

# winget "no installed package found" (0x8A150014)
$NotInstalledExitCode = -1978335212

function Find-Winget {
    if ($IsAdmin) {
        # Folder names sort as text (1.100 < 1.29), so pick the newest by version
        $folder = Get-ChildItem -Path 'C:\Program Files\WindowsApps' -Directory -Filter 'Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe' |
            Where-Object { Test-Path (Join-Path $_.FullName 'winget.exe') } |
            Sort-Object { [version]($_.Name -split '_')[1] } | Select-Object -Last 1
        if ($folder) { return Join-Path $folder.FullName 'winget.exe' }
    }
    else {
        $exe = Resolve-Path "$env:LOCALAPPDATA\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller*\winget.exe" | Select-Object -Last 1
        if ($exe) { return $exe.Path }
    }
    return $null
}

function Invoke-WingetList([string]$Winget) {
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $Winget
    $processInfo.Arguments = "list --id $app --exact --accept-source-agreements"
    $processInfo.RedirectStandardOutput = $true
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::Start($processInfo)
    $output = $process.StandardOutput.ReadToEndAsync()
    if (-not $process.WaitForExit(120000)) {
        $process.Kill()
        return [pscustomobject]@{ ExitCode = $null; Output = '' }
    }
    return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $output.Result }
}

$winget = Find-Winget
if (-not $winget -and -not $IsAdmin) {
    # At a user's first logon Windows registers App Installer (winget) asynchronously
    try { Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction Stop } catch { }
}
for ($attempt = 1; -not $winget -and $attempt -le 4; $attempt++) {
    Start-Sleep -Seconds 5
    $winget = Find-Winget
}
if (-not $winget) {
    [Console]::Error.WriteLine("winget not found (IsAdmin=$IsAdmin)")
    exit 1
}

$errorText = ''
for ($attempt = 1; $attempt -le 3; $attempt++) {
    $result = Invoke-WingetList $winget
    if ($result.ExitCode -eq 0) {
        if ($result.Output -like "*$app*") { Write-Output "Installed" }
        exit 0
    }
    if ($result.ExitCode -eq $NotInstalledExitCode) {
        exit 0
    }
    $errorText = if ($null -eq $result.ExitCode) { 'winget did not finish within 120 seconds' } else { 'winget list failed with exit code 0x{0:X8}' -f $result.ExitCode }
    if ($attempt -lt 3) { Start-Sleep -Seconds 5 }
}
[Console]::Error.WriteLine("$errorText ($winget)")
exit 1
