#Requires -Version 5.1

<#
.SYNOPSIS
    Runs the WingetFW (PSADT v3) test suite on a sandbox VM.

.DESCRIPTION
    Runs Deploy-Application.exe with every WingetFW parameter for all winget actions
    (install, uninstall, upgrade, repair, import) and checks each run:
      - exit code of Deploy-Application.exe
      - the winget command line logged by Execute-Process in the toolkit log
      - log messages (validation errors, skipped options)
      - the state on the machine afterwards (package installed/removed, files, version)

    Admin-mode tests run as SYSTEM through PsExec (like Intune). User-mode tests run as
    the current user without PsExec. Before every run a marker line with the run-as
    account and the full command (including PsExec) is written to the toolkit log.

    The winget admin settings needed for some parameters (LocalManifestFiles,
    InstallerHashOverride, LocalArchiveMalwareScanOverride, ProxyCommandLineOptions)
    are enabled during the run and restored afterwards.

    Output in <Root>\results:
      WingetFW-TestResults.log   readable log of all tests
      WingetFW-TestResults.json  machine readable results (used for TEST-RESULTS.md)

.PARAMETER Root
    Folder on the VM that contains the WingetFW package folder. Must not be in a user profile
    (SYSTEM must be able to read it).

.PARAMETER PackageFolder
    Name of the package folder in -Root. WinGetFW5.0.0 (Invoke-AppDeployToolkit.exe, PSADT 4) or
    WinGetFW (Deploy-Application.exe, PSADT 3). The package type is detected from the exe.

.PARAMETER PsExecPath
    Path to PsExec64.exe on the VM.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\temp\wingetfw-vmtest\Invoke-WingetFWTestSuite.ps1 -PackageFolder WinGetFW5.0.0

.NOTES
    Maintained by: KSKITDK
    Version      : 1.5.0

    Release notes
    1.5.0  - M01-M13: mod files (order of the sections, $Settings, 69002, failure sections, load check, signature,
             AllowedScriptSources, UNC, Azure blob simulated with a local web server, Mirror, offline cache,
             user mode). A test code signing certificate is added to LocalMachine and removed at the end.
    1.4.0  - S01-S12: settings from policy (HKLM\SOFTWARE\Policies\WingetFW), command line, local key
             (HKLM\SOFTWARE\WingetFW) and config file: order, DefaultSilent, DefaultSource, AllowedSources,
             Sources, TlsCheck. The keys and the config file are reset before every S test and at the end.
    1.3.0  - Runs against WingetFW 5.0.0 (Invoke-AppDeployToolkit.exe, PSADT 4) or 4.0.8 (Deploy-Application.exe);
             the package folder is set with -PackageFolder. The Q tests check the quoting of the exe used.
    1.2.1  - The toolkit log folder is created at the start, so the suite also runs on a clean VM.
           - U05: winget is linked in after WingetFW logs retry attempt 2 instead of after a fixed
             10 seconds, so the test no longer fails when the App Installer registration call is slow.
    1.2.0  - F02/F15: winget "already installed" exit codes on install are logged and give exit code 0.
           - U05/U06: user mode where winget appears a few seconds late (first logon race).
           - Maintainer set to KSKITDK, GitHub link added.
    1.1.0  - V10: -header without -source must stop with 60001.
           - F02: -source winget added, winget rejects --header without --source.
           - U03/U04: Postman.Postman as a real user-scope installer (EXE) in user mode.
    1.0.0  - First version: validation, admin (SYSTEM via PsExec), portable and user-mode tests.

.LINK
    https://github.com/ksk-itdk/PSADT-WingetFW
#>
[CmdletBinding()]
Param (
    [Parameter()]
    [String]$Root = 'C:\temp\wingetfw-vmtest',

    [Parameter()]
    [String]$PackageFolder = 'WinGetFW5.0.0',

    [Parameter()]
    [String]$PsExecPath = 'C:\temp\PSTools\PsExec64.exe'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$pkgDir        = Join-Path $Root $PackageFolder
$isV4          = Test-Path (Join-Path $pkgDir 'Invoke-AppDeployToolkit.exe')
$exeName       = If ($isV4) { 'Invoke-AppDeployToolkit.exe' } Else { 'Deploy-Application.exe' }
$exe           = Join-Path $pkgDir $exeName
$deployScript  = Get-Content (Join-Path $pkgDir ([IO.Path]::ChangeExtension($exeName, '.ps1'))) -Raw
$resultDir     = Join-Path $Root 'results'
$tmpDir        = Join-Path $Root 'tmp'
$spaceDir      = Join-Path $Root 'path with spaces'
$resultLog     = Join-Path $resultDir 'WingetFW-TestResults.log'
$resultJson    = Join-Path $resultDir 'WingetFW-TestResults.json'
$toolkitLogDir = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$appVersion    = [regex]::Match($deployScript, "(?im)^\s*(\[String\]\`$)?appVersion = '([^']+)'").Groups[2].Value
$psadtVersion  = [regex]::Match($deployScript, "(?i)deployAppScriptVersion = (\[Version\])?'([^']+)'").Groups[2].Value

If (-not (Test-Path $exe)) { Throw "$exeName not found: $exe" }
If (-not (Test-Path $PsExecPath)) { Throw "PsExec not found: $PsExecPath" }
If (Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'Deploy-Application|Invoke-AppDeployToolkit' }) { Throw 'Another WingetFW deployment is running on this VM - aborting.' }
New-Item -ItemType Directory -Path $resultDir, $tmpDir, $spaceDir, $toolkitLogDir -Force | Out-Null
Remove-Item (Join-Path $resultDir '*'), (Join-Path $tmpDir '*'), (Join-Path $spaceDir '*') -Force -Recurse -ErrorAction SilentlyContinue

Function Write-Result([String]$Text) { Add-Content -Path $resultLog -Value $Text -Encoding UTF8; Write-Output $Text }

# Both exes run the args through powershell.exe -Command (v3 also strips double quotes), so values with
# spaces or PowerShell special characters ({ } $ ; ( ) @ & ...) must use single quotes
Function Join-ArgString([String[]]$ArgList) {
    ($ArgList | ForEach-Object { If ($_ -match '[\s''"{}$;()@&|<>,`]') { "'" + ($_ -replace "'", "''") + "'" } Else { $_ } }) -join ' '
}

# Same CMTrace line format as Write-Log in AppDeployToolkitMain.ps1
Function Write-ToolkitLogMarker([String]$LogFile, [String]$Message) {
    $now = Get-Date
    $bias = [TimeZone]::CurrentTimeZone.GetUtcOffset($now).TotalMinutes
    $line = "<![LOG[$Message]LOG]!><time=`"$($now.ToString('HH\:mm\:ss.fff'))$bias`" date=`"$($now.ToString('MM-dd-yyyy'))`" component=`"WingetFW-Test`" context=`"$([Security.Principal.WindowsIdentity]::GetCurrent().Name)`" type=`"1`" thread=`"$PID`" file=`"Invoke-WingetFWTestSuite.ps1`">"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

Function Invoke-AsSystem([String]$FilePath, [String]$Arguments) {
    $psArgs = "-accepteula -nobanner -s -w `"$pkgDir`" `"$FilePath`" $Arguments"
    $p = Start-Process -FilePath $PsExecPath -ArgumentList $psArgs -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput (Join-Path $tmpDir 'psexec-out.txt') -RedirectStandardError (Join-Path $tmpDir 'psexec-err.txt')
    [PSCustomObject]@{ ExitCode = $p.ExitCode; Command = "$PsExecPath $psArgs" }
}

$wingetSystem = Join-Path (Resolve-Path 'C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe')[-1].Path 'winget.exe'

# PsExec does not relay winget's console output reliably, so cmd.exe redirects it to a file as SYSTEM
Function Invoke-WingetAsSystem([String]$Arguments, [Switch]$Quiet) {
    $out = Join-Path $tmpDir ('winget-{0}.txt' -f [guid]::NewGuid().ToString('N'))
    $r = Invoke-AsSystem 'cmd.exe' "/c `"`"$wingetSystem`" $Arguments > `"$out`" 2>&1`""
    $text = If (Test-Path $out) { (Get-Content $out -Raw) -replace '[\b]', '' } Else { '' }
    If (-not $Quiet) { Write-Result "  [setup] SYSTEM via PsExec: winget $Arguments -> exit $(Format-ExitCode $r.ExitCode)" }
    [PSCustomObject]@{ ExitCode = $r.ExitCode; Output = $text }
}

Function Format-ExitCode([Int]$Code) { If ($Code -lt 0) { '{0} (0x{1:X8})' -f $Code, $Code } Else { "$Code" } }

Function Get-7Zip {
    Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' | Get-ItemProperty | Where-Object { $_.DisplayName -like '7-Zip*' } |
        Select-Object -First 1 @{ n = 'Version'; e = { $_.DisplayVersion } }, @{ n = 'ProductCode'; e = { If ($_.WindowsInstaller -eq 1) { $_.PSChildName } } }, @{ n = 'Msi'; e = { $_.WindowsInstaller -eq 1 } }
}
Function Get-JqMachineFolder { Get-ChildItem 'C:\Program Files\WinGet\Packages' -Directory -Filter 'jqlang.jq*' -ErrorAction SilentlyContinue | Select-Object -First 1 }
Function Get-JqUserFolder { Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Directory -Filter 'jqlang.jq*' -ErrorAction SilentlyContinue | Select-Object -First 1 }
# Key name = ProductCode 'Postman' from the winget manifest
Function Get-PostmanUser { Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Postman' -ErrorAction SilentlyContinue }
# U05 links the real WindowsApps folder in with a junction; rmdir removes only the link, never the target
Function Remove-FakeLocalAppData {
    $fake = Join-Path $Root 'first logon localappdata'
    If (Test-Path "$fake\Microsoft\WindowsApps") { cmd.exe /c rmdir "$fake\Microsoft\WindowsApps" | Out-Null }
    If (Test-Path "$fake\Microsoft\WindowsApps") { Throw "Could not remove the junction $fake\Microsoft\WindowsApps" }
    Remove-Item $fake -Recurse -Force -ErrorAction SilentlyContinue
}

$script:results = New-Object System.Collections.Generic.List[Object]
Function Invoke-Test {
    Param(
        [String]$Id, [String]$Title, [ValidateSet('Admin', 'User')][String]$Mode = 'Admin', [String[]]$ArgList,
        # $null = any exit code is accepted (informational test)
        [Object]$ExpectExit = @(0),
        [String[]]$ExpectLog = @(), [String[]]$ExpectNotLog = @(), [Object[]]$Flags = @(), [Object[]]$NotFlags = @(), [ScriptBlock]$State,
        # Passed to Deploy-Application.exe as-is instead of building it from ArgList
        [String]$RawArgs,
        # Runs before Deploy-Application.exe, its text output is written to the results log
        [ScriptBlock]$Pre
    )

    # User mode runs in a user session: Silent would show a blocking error dialog on failure
    $deployMode = If ($Mode -eq 'User') { 'NonInteractive' } Else { 'Silent' }
    $argList = @('-DeploymentType') + $ArgList + @('-DeployMode', $deployMode)
    If ($Mode -eq 'User') { $argList += @('-Mode', 'User') }
    $argString = If ($RawArgs) { $RawArgs } Else { Join-ArgString $argList }

    # Toolkit log name: <OverrideAPPName|id|name>_WingetFW_<ver>_EN_01_PSAppDeployToolkit_<DeploymentType>.log
    $named = @{}
    For ($i = 0; $i -lt $argList.Count; $i++) {
        If ($argList[$i] -like '-*') { $named[$argList[$i].TrimStart('-')] = If ($i + 1 -lt $argList.Count -and $argList[$i + 1] -notlike '-*') { $argList[$i + 1] } Else { $true } }
    }
    $vendor = @($named['OverrideAPPName'], $named['id'], $named['name']) | Where-Object { $_ -is [String] } | Select-Object -First 1
    $installName = ((("$vendor" + "_WingetFW_$appVersion" + '_EN_01') -replace ' ', '').Trim('_') -replace '[_]+', '_')
    $toolkitLog = Join-Path $toolkitLogDir "$($installName)_PSAppDeployToolkit_$($named['DeploymentType']).log"
    $startLength = If (Test-Path $toolkitLog) { (Get-Item $toolkitLog).Length } Else { 0 }

    If ($Mode -eq 'Admin') {
        $runAs = 'SYSTEM via PsExec'
        $display = "$PsExecPath -accepteula -nobanner -s -w `"$pkgDir`" `"$exe`" $argString"
    }
    Else {
        $runAs = "$env:USERNAME (no PsExec)"
        $display = "`"$exe`" $argString"
    }
    Write-Result ''
    Write-Result ('=' * 110)
    Write-Result "[$Id] $Title"
    Write-Result "Run as      : $runAs"
    Write-Result "Command     : $display"
    Write-Result "Toolkit log : $toolkitLog"
    Write-ToolkitLogMarker $toolkitLog "[TEST $Id] $Title | Run as: $runAs | Command: $display"
    If ($Pre) { & $Pre | ForEach-Object { Write-Result "Pre step    : $_" } }

    $sw = [Diagnostics.Stopwatch]::StartNew()
    If ($Mode -eq 'Admin') { $exitCode = (Invoke-AsSystem $exe $argString).ExitCode }
    Else { $exitCode = (Start-Process -FilePath $exe -ArgumentList $argString -Wait -PassThru).ExitCode }
    $sw.Stop()

    $raw = ''
    If (Test-Path $toolkitLog) {
        $fs = [IO.File]::Open($toolkitLog, 'Open', 'Read', 'ReadWrite'); $fs.Position = $startLength
        $raw = (New-Object IO.StreamReader($fs)).ReadToEnd(); $fs.Close()
    }
    $entries = @([regex]::Matches($raw, '(?s)<!\[LOG\[(.*?)\]LOG\]!><time="([^"]*)"[^>]*component="([^"]*)"[^>]*type="(\d)"') | ForEach-Object {
        [PSCustomObject]@{ Message = $_.Groups[1].Value.Trim(); Time = $_.Groups[2].Value.Substring(0, 12); Component = $_.Groups[3].Value; Type = [Int]$_.Groups[4].Value }
    })
    $executes = @($entries | Where-Object { $_.Component -in @('Execute-Process', 'Start-ADTProcess') } | ForEach-Object { If ($_.Message -match ':: Executing \[.*?winget\.exe"? (.*)\]\.\.\.$') { $Matches[1].Trim() } })

    $checks = New-Object System.Collections.Generic.List[Object]
    If ($null -eq $ExpectExit) { $checks.Add([PSCustomObject]@{ Ok = $true; Text = "exit code $(Format-ExitCode $exitCode) (informational, any accepted)" }) }
    Else { $checks.Add([PSCustomObject]@{ Ok = (@($ExpectExit) -contains $exitCode); Text = "exit code $(Format-ExitCode $exitCode) (expected $((@($ExpectExit) | ForEach-Object { Format-ExitCode $_ }) -join ' or '))" }) }
    $checks.Add([PSCustomObject]@{ Ok = (@($entries | Where-Object { $_.Message -like "*``[TEST $Id``]*" }).Count -eq 1); Text = 'run marker (run as / PsExec command) written to toolkit log' })
    For ($n = 0; $n -lt $Flags.Count; $n++) {
        ForEach ($f in @($Flags[$n])) { $checks.Add([PSCustomObject]@{ Ok = ($executes.Count -gt $n -and $executes[$n].Contains($f)); Text = "winget call $($n + 1) contains: $f" }) }
    }
    For ($n = 0; $n -lt $NotFlags.Count; $n++) {
        ForEach ($f in @($NotFlags[$n])) { $checks.Add([PSCustomObject]@{ Ok = ($executes.Count -gt $n -and -not $executes[$n].Contains($f)); Text = "winget call $($n + 1) does NOT contain: $f" }) }
    }
    ForEach ($p in $ExpectLog) { $checks.Add([PSCustomObject]@{ Ok = [Bool]($entries | Where-Object { $_.Message -match $p }); Text = "toolkit log contains: $p" }) }
    ForEach ($p in $ExpectNotLog) { $checks.Add([PSCustomObject]@{ Ok = -not ($entries | Where-Object { $_.Component -ne 'WingetFW-Test' -and $_.Message -match $p }); Text = "toolkit log does NOT contain: $p" }) }
    If ($State) { $s = & $State; $checks.Add([PSCustomObject]@{ Ok = [Bool]$s.Ok; Text = "state: $($s.Text)" }) }

    $pass = -not ($checks | Where-Object { -not $_.Ok })
    Write-Result "Duration    : $([Int]$sw.Elapsed.TotalSeconds) s"
    For ($n = 0; $n -lt $executes.Count; $n++) { Write-Result "winget $($n + 1)    : $($executes[$n])" }
    If (-not $executes) { Write-Result 'winget      : (not executed)' }
    Write-Result 'Checks      :'
    $checks | ForEach-Object { Write-Result ('   [{0}] {1}' -f $(If ($_.Ok) { 'OK  ' } Else { 'FAIL' }), $_.Text) }
    Write-Result "Result      : $(If ($pass) { 'PASS' } Else { 'FAIL' })"
    Write-Result 'Toolkit log excerpt:'
    $excerpt = @($entries | Where-Object { $_.Component -in @('WingetFW-Test', 'Start-WinGetPackageFM', 'Execute-Process', 'Exit-Script', 'Start-ADTProcess', 'Close-ADTSession') -or $_.Type -ge 2 } |
        Where-Object { $_.Message -notmatch '^(Installing|Done installing|UserMode:)' } |
        ForEach-Object { '{0} [{1}]{2} {3}' -f $_.Time, $_.Component, $(If ($_.Type -eq 3) { ' [Error]' } ElseIf ($_.Type -eq 2) { ' [Warning]' } Else { '' }), (($_.Message -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 4) -join ' | ') })
    $excerpt | ForEach-Object { Write-Result "   $_" }

    $script:results.Add([PSCustomObject]@{
        Id = $Id; Title = $Title; Mode = $Mode; RunAs = $runAs; Command = $display; ToolkitLog = $toolkitLog
        Parameters = @($argList | Where-Object { $_ -like '-*' -and $_ -notin @('-DeploymentType', '-DeployMode', '-Mode') } | ForEach-Object { $_.TrimStart('-') })
        DeploymentType = $named['DeploymentType']; Action = $(If ($named['Action'] -is [String]) { $named['Action'] } Else { $named['DeploymentType'] })
        ExitCode = $exitCode; ExitText = (Format-ExitCode $exitCode); DurationSec = [Int]$sw.Elapsed.TotalSeconds
        WingetCalls = $executes; Checks = $checks.ToArray(); Result = $(If ($pass) { 'PASS' } Else { 'FAIL' }); LogExcerpt = $excerpt
    })
}

# ---------------------------------------------------------------- setup
Write-Result "WingetFW $appVersion test run $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') on $env:COMPUTERNAME (runner user: $env:USERNAME)"
Write-Result "Package       : $exe (PSADT $psadtVersion)"
Write-Result "SYSTEM winget : $wingetSystem"
$wingetVersion = (Invoke-WingetAsSystem '--version' -Quiet).Output.Trim()
$osVersion = (Get-CimInstance Win32_OperatingSystem | ForEach-Object { "$($_.Caption) $($_.Version)" })
Write-Result "winget version: $wingetVersion"
Write-Result "OS            : $osVersion"
Write-Result ''
Write-Result 'SETUP'
$adminSettings = @('LocalManifestFiles', 'InstallerHashOverride', 'LocalArchiveMalwareScanOverride', 'ProxyCommandLineOptions')
# Original state is kept in a file so an aborted run is still restored by the next run
$stateFile = Join-Path $Root 'winget-adminsettings-original.json'
If (Test-Path $stateFile) {
    $before = Get-Content $stateFile -Raw | ConvertFrom-Json
    Write-Result "  winget admin settings original state read from $stateFile (previous run was aborted)"
}
Else {
    $export = (Invoke-WingetAsSystem 'settings export' -Quiet).Output
    $before = $export.Substring($export.IndexOf('{'), $export.LastIndexOf('}') - $export.IndexOf('{') + 1) | ConvertFrom-Json
    [PSCustomObject]@{ adminSettings = $before.adminSettings } | ConvertTo-Json | Set-Content $stateFile -Encoding UTF8
}
Write-Result "  winget admin settings before: $(($adminSettings | ForEach-Object { "$_=$($before.adminSettings.$_)" }) -join ', ')"
$adminSettings | Where-Object { -not $before.adminSettings.$_ } | ForEach-Object { Invoke-WingetAsSystem "settings --enable $_" | Out-Null }
Invoke-WingetAsSystem 'uninstall --id 7zip.7zip --exact --silent --all-versions --accept-source-agreements --disable-interactivity' | Out-Null
Invoke-WingetAsSystem 'uninstall --id jqlang.jq --exact --silent --all-versions --accept-source-agreements --disable-interactivity' | Out-Null
# Postman is installed per user, so SYSTEM cannot remove it
Remove-FakeLocalAppData
If (Get-PostmanUser) {
    Stop-Process -Name 'Postman' -Force -ErrorAction SilentlyContinue
    & (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe') uninstall --id Postman.Postman --exact --silent --accept-source-agreements --disable-interactivity | Out-Null
    Write-Result "  [setup] $($env:USERNAME): winget uninstall --id Postman.Postman -> exit $(Format-ExitCode $LASTEXITCODE)"
}

$versions = @((Invoke-WingetAsSystem 'show 7zip.7zip --versions --accept-source-agreements --disable-interactivity' -Quiet).Output -split '[\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+(\.\d+)+$' })
If ($versions.Count -lt 2) { Throw "Could not read 7zip.7zip versions from winget (got: $($versions -join ', '))" }
$latest = $versions[0]; $old = $versions[1]
Write-Result "  7zip.7zip latest=$latest older=$old"

$manifestDir = Join-Path $spaceDir "manifest 7zip $old"
New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
# PS 5.1 Invoke-RestMethod emits a JSON array as one object, so assign before enumerating
$manifestFiles = Invoke-RestMethod "https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/7/7zip/7zip/$old" -UseBasicParsing
ForEach ($file in $manifestFiles) { Invoke-WebRequest $file.download_url -OutFile (Join-Path $manifestDir $file.name) -UseBasicParsing }
Write-Result "  manifest $old downloaded: $((Get-ChildItem $manifestDir).Name -join ', ')"

$importFile = Join-Path $spaceDir 'import apps.json'
@{ '$schema' = 'https://aka.ms/winget-packages.schema.2.0.json'; WinGetVersion = $wingetVersion.TrimStart('v')
   Sources = @(@{ SourceDetails = @{ Name = 'winget'; Argument = 'https://cdn.winget.microsoft.com/cache'; Identifier = 'Microsoft.Winget.Source_8wekyb3d8bbwe'; Type = 'Microsoft.PreIndexed.Package' }
                  Packages = @(@{ PackageIdentifier = '7zip.7zip'; Version = $old }) }) } | ConvertTo-Json -Depth 6 | Set-Content $importFile -Encoding UTF8
Write-Result "  import file   : $importFile"

$wingetLogDir = Join-Path $spaceDir 'winget logs'
$jqLocation = Join-Path $spaceDir 'jq portable'
New-Item -ItemType Directory -Path $wingetLogDir -Force | Out-Null
$installed = { $z = Get-7Zip; [PSCustomObject]@{ Ok = [Bool]$z; Text = "7-Zip installed ($($z.Version), msi=$($z.Msi))" } }
$notInstalled = { $z = Get-7Zip; [PSCustomObject]@{ Ok = -not $z; Text = "7-Zip not installed$(If ($z) { " (found $($z.Version))" })" } }
$noPackageAgreement = @('--accept-package-agreements')

# WingetFW settings levels used by the S tests; reset here too, in case an earlier run was aborted
$policyKey = 'HKLM:\SOFTWARE\Policies\WingetFW'
$localKey = 'HKLM:\SOFTWARE\WingetFW'
$configFile = Join-Path $pkgDir 'PSAppDeployToolkit.Extensions\Config\WingetFW.psd1'
$configOriginal = If (Test-Path $configFile) { [IO.File]::ReadAllText($configFile) } Else { $null }
Function Reset-WingetFWSettings {
    Remove-Item $policyKey, $localKey -Recurse -Force -ErrorAction SilentlyContinue
    If ($null -ne $configOriginal) { [IO.File]::WriteAllText($configFile, $configOriginal) }
}
# Arrays and tables are written like ADMX list elements: a subkey with values 1, 2, 3 ... or name = value
Function Set-WingetFWTestSetting([ValidateSet('Policy', 'Local')][String]$Level, [String]$Name, [Object]$Value) {
    $key = If ($Level -eq 'Policy') { $policyKey } Else { $localKey }
    # New-Item -Force on an existing registry key recreates it and drops its values
    If (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    If ($Value -is [Collections.IDictionary]) {
        $sub = New-Item -Path (Join-Path $key $Name) -Force
        ForEach ($k in $Value.Keys) { New-ItemProperty -Path $sub.PSPath -Name $k -Value $Value[$k] -Force | Out-Null }
        $text = ($Value.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; '
    }
    ElseIf ($Value -is [Array]) {
        $sub = New-Item -Path (Join-Path $key $Name) -Force
        For ($i = 0; $i -lt $Value.Count; $i++) { New-ItemProperty -Path $sub.PSPath -Name ($i + 1) -Value $Value[$i] -Force | Out-Null }
        $text = $Value -join '; '
    }
    ElseIf ($Value -is [Int]) { New-ItemProperty -Path $key -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null; $text = "$Value (DWORD)" }
    Else { New-ItemProperty -Path $key -Name $Name -Value $Value -PropertyType String -Force | Out-Null; $text = $Value }
    "$Level $Name = $text"
}
Function Set-WingetFWTestConfig([Hashtable]$Settings) {
    $lines = @('@{', '    TlsCheck = $false', '    VCRedistCheck = $false') + @($Settings.GetEnumerator() | ForEach-Object { "    $($_.Key) = '$($_.Value)'" }) + @('}')
    [IO.File]::WriteAllText($configFile, ($lines -join "`r`n"))
    "config file: $(($Settings.GetEnumerator() | ForEach-Object { "$($_.Key) = $($_.Value)" }) -join '; ')"
}
Reset-WingetFWSettings

# ---------------------------------------------------------------- validation: must stop before winget runs
# Conflict messages list the parameters in binding order, so only the fixed 'Use only one of' part is checked
Invoke-Test -Id 'V01' -Title 'Install: -id + -name conflict' -ArgList @('Install', '-id', '7zip.7zip', '-name', '7-Zip') -ExpectExit 60001 -ExpectLog @('cannot be used together\. Use only one of -wingetmanifest, -id, -name, -moniker')
Invoke-Test -Id 'V02' -Title 'Install: -interactive + -silent conflict' -ArgList @('Install', '-id', '7zip.7zip', '-interactive', '-silent') -ExpectExit 60001 -ExpectLog @('cannot be used together\. Use only one of -interactive, -silent, -override')
Invoke-Test -Id 'V03' -Title 'Install: -silent + -override conflict' -ArgList @('Install', '-id', '7zip.7zip', '-silent', '-override', '/S') -ExpectExit 60001 -ExpectLog @('cannot be used together\. Use only one of -interactive, -silent, -override')
Invoke-Test -Id 'V04' -Title 'Install: -proxy + -noproxy conflict' -ArgList @('Install', '-id', '7zip.7zip', '-proxy', 'http://127.0.0.1:9', '-noproxy') -ExpectExit 60001 -ExpectLog @('cannot be used together\. Use only one of -proxy, -noproxy')
Invoke-Test -Id 'V05' -Title 'Uninstall: -override not supported' -ArgList @('Uninstall', '-id', '7zip.7zip', '-override', '/S') -ExpectExit 60001 -ExpectLog @('-override is not an option with winget Uninstall')
Invoke-Test -Id 'V06' -Title 'Uninstall: -purge + -preserve conflict' -ArgList @('Uninstall', '-id', 'jqlang.jq', '-purge', '-preserve') -ExpectExit 60001 -ExpectLog @('cannot be used together\. Use only one of -purge, -preserve')
Invoke-Test -Id 'V07' -Title 'Import: -id not supported' -ArgList @('Install', '-Action', 'import', '-importfile', $importFile, '-id', '7zip.7zip') -ExpectExit 60001 -ExpectLog @('-id is not an option with winget import')
Invoke-Test -Id 'V08' -Title 'Repair: -custom not supported' -ArgList @('Repair', '-id', '7zip.7zip', '-custom', 'X=1') -ExpectExit 60001 -ExpectLog @('-custom is not an option with winget Repair')
Invoke-Test -Id 'V09' -Title 'Upgrade: -rename not supported' -ArgList @('Install', '-Action', 'upgrade', '-id', '7zip.7zip', '-rename', 'x.exe') -ExpectExit 60001 -ExpectLog @('-rename is not an option with winget upgrade')
Invoke-Test -Id 'V10' -Title 'Install: -header without -source' -ArgList @('Install', '-id', '7zip.7zip', '-header', 'X-WingetFW-Test: 1') -ExpectExit 60001 -ExpectLog @('-header requires -source')
Invoke-Test -Id 'N01' -Title 'Install: no package specified fails with 69001' -ArgList @('Install', '-silent') -ExpectExit 69001 -ExpectLog @('No package specified')

# ---------------------------------------------------------------- exe quoting (known behaviour of Deploy-Application.exe / Invoke-AppDeployToolkit.exe)
If ($isV4) {
    # Invoke-AppDeployToolkit.exe builds powershell.exe -Command "try { & '<script>' <args> } ...", so a double quote ends that string
    Invoke-Test -Id 'Q01' -Title "$($exeName): double-quoted value with spaces breaks the command - script does not start, exit 1" -ArgList @('Install', '-id', '7zip.7zip', '-name', '7 Zip') `
        -RawArgs '-DeploymentType Install -id 7zip.7zip -name "7 Zip" -DeployMode Silent' -ExpectExit 1 -ExpectNotLog @('Start-WinGetPackageFM', 'cannot be used together', 'completed in')
}
Else {
    Invoke-Test -Id 'Q01' -Title "$($exeName): double-quoted value with spaces is split - script does not start, exit 0" -ArgList @('Install', '-id', '7zip.7zip', '-name', '7 Zip') `
        -RawArgs '-DeploymentType Install -id 7zip.7zip -name "7 Zip" -DeployMode Silent' -ExpectExit 0 -ExpectNotLog @('Start-WinGetPackageFM', 'cannot be used together', 'Installation completed')
}
Invoke-Test -Id 'Q02' -Title "$($exeName): single-quoted value with spaces is passed correctly" -ArgList @('Install', '-id', '7zip.7zip', '-name', '7 Zip') `
    -RawArgs "-DeploymentType Install -id 7zip.7zip -name '7 Zip' -DeployMode Silent" -ExpectExit 60001 -ExpectLog @('cannot be used together\. Use only one of -wingetmanifest, -id, -name, -moniker')
Invoke-Test -Id 'Q03' -Title "$($exeName): unquoted {GUID} loses its braces (PowerShell script block)" -ArgList @('Uninstall', '-productcode', '{00000000-0000-0000-0000-000000000000}') `
    -RawArgs '-DeploymentType Uninstall -productcode {00000000-0000-0000-0000-000000000000} -silent -DeployMode Silent' -ExpectExit @(-1978335212) `
    -Flags @(, @('--product-code 00000000-0000-0000-0000-000000000000')) -NotFlags @(, @('{00000000'))

# ---------------------------------------------------------------- functional, Admin mode (SYSTEM via PsExec)
$f01log = Join-Path $wingetLogDir 'F01 install.log'
Invoke-Test -Id 'F01' -Title 'Install: older MSI (WiX) version with install options' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-version', $old, '-scope', 'Machine', '-architecture', 'X64', '-installertype', 'Wix', '-silent', '-log', $f01log, '-source', 'winget', '-dependencysource', 'winget', '-skipdependencies', '-allowreboot', '-custom', 'REBOOT=ReallySuppress', '-ignoresecurityhash', '-enableverbose', '-ignorewarnings', '-disableinteractivity', '-noproxy') `
    -Flags @(, @('--id 7zip.7zip', '--exact', "--version $old", '--scope machine', '--architecture x64', '--installer-type wix', '--silent', "--log `"$f01log`"", '--source winget', '--dependency-source winget', '--skip-dependencies', '--allow-reboot', '--custom "REBOOT=ReallySuppress"', '--ignore-security-hash', '--verbose', '--ignore-warnings', '--disable-interactivity', '--no-proxy', '--accept-package-agreements', '--accept-source-agreements')) `
    -ExpectLog @("-Action Install .*-id '7zip\.7zip'.*-skipdependencies", 'Running winget Install for \[7zip\.7zip\]', 'Done: winget Install for \[7zip\.7zip\]') `
    -State { $z = Get-7Zip; [PSCustomObject]@{ Ok = ($z -and $z.Msi -and $z.Version -like "$old*" -and (Test-Path $f01log)); Text = "7-Zip $($z.Version) msi=$($z.Msi), winget log file created=$(Test-Path $f01log)" } }

Invoke-Test -Id 'F02' -Title 'Install: -noupgrade on installed package (+interactive, locale, source, header, auth) - logged as already installed, exit 0' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-source', 'winget', '-noupgrade', '-interactive', '-locale', 'en-US', '-header', 'X-WingetFW-Test: 1', '-authenticationmode', 'silentPreferred', '-authenticationaccount', 'wingetfw@contoso.com') `
    -ExpectLog @('\[7zip\.7zip\] is already installed, nothing to install \(winget exit code 0x8A150061\)') `
    -Flags @(, @('--source winget', '--no-upgrade', '--interactive', '--locale en-US', '--header "X-WingetFW-Test: 1"', '--authentication-mode silentPreferred', '--authentication-account wingetfw@contoso.com')) -State $installed

Invoke-Test -Id 'F03' -Title 'Upgrade: to latest (-Action upgrade)' -ArgList @('Install', '-Action', 'upgrade', '-id', '7zip.7zip', '-exact', '-silent', '-includeunknown', '-includepinned', '-uninstallprevious', '-force') `
    -Flags @(, @('upgrade', '--include-unknown', '--include-pinned', '--uninstall-previous', '--force')) `
    -State { $z = Get-7Zip; [PSCustomObject]@{ Ok = ($z -and $z.Version -notlike "$old*"); Text = "7-Zip $($z.Version) (older was $old)" } }

Invoke-Test -Id 'F15' -Title 'Install: package already installed with the latest version - logged as already installed, exit 0' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent') `
    -ExpectLog @('\[7zip\.7zip\] is already installed, nothing to install \(winget exit code 0x8A15002B\)') -State $installed

# 7-Zip MSI repair fails inside winget (0x8A15007B EXEC_REPAIR_FAILED); the test checks WingetFW builds the right command
Invoke-Test -Id 'F04' -Title 'Repair: winget repair by -id (informational: 7-Zip MSI repair itself may fail in winget)' -ArgList @('Repair', '-id', '7zip.7zip', '-exact', '-silent', '-force') -ExpectExit @(0, -1978335109) -Flags @(, @('Repair', '--id 7zip.7zip', '--force')) -State $installed

$code = (Get-7Zip).ProductCode
Invoke-Test -Id 'F05' -Title 'Repair: winget repair by -productcode (informational: 7-Zip MSI repair itself may fail in winget)' -ArgList @('Repair', '-productcode', "$code", '-silent') -ExpectExit @(0, -1978335109) -Flags @(, @("--product-code $code")) -State $installed

Invoke-Test -Id 'F06' -Title 'ForceRepair: uninstall skips install-only options, install uses them' -ArgList @('Repair', '-ForceRepair', '-id', '7zip.7zip', '-exact', '-silent', '-scope', 'Machine', '-allowreboot', '-skipdependencies', '-custom', 'REBOOT=ReallySuppress') `
    -ExpectLog @('Skipping -allowreboot', 'Skipping -skipdependencies', 'Skipping -custom') `
    -Flags @(@('uninstall', '--scope machine'), @('install', '--allow-reboot', '--skip-dependencies', '--custom "REBOOT=ReallySuppress"')) `
    -NotFlags @(, @('--allow-reboot', '--skip-dependencies', '--custom', '--accept-package-agreements')) -State $installed

$code = (Get-7Zip).ProductCode
Invoke-Test -Id 'F07' -Title 'Uninstall: by -productcode' -ArgList @('Uninstall', '-productcode', "$code", '-silent', '-force') -Flags @(, @("--product-code $code", '--force')) -NotFlags @(, $noPackageAgreement) -State $notInstalled

Invoke-Test -Id 'F08' -Title 'Install: local manifest folder (path with spaces)' -ArgList @('Install', '-wingetmanifest', $manifestDir, '-silent', '-scope', 'Machine', '-ignorelocalarchivemalwarescan') `
    -Flags @(, @("--manifest `"$manifestDir`"", '--ignore-local-archive-malware-scan')) -State { $z = Get-7Zip; [PSCustomObject]@{ Ok = ($z -and $z.Version -like "$old*"); Text = "7-Zip $($z.Version) (manifest $old)" } }

Invoke-Test -Id 'F09' -Title 'Uninstall: by -moniker' -ArgList @('Uninstall', '-moniker', '7zip', '-silent') -Flags @(, @('--moniker 7zip')) -NotFlags @(, $noPackageAgreement) -State $notInstalled

Invoke-Test -Id 'F10' -Title 'Import: JSON file (path with spaces) with -ignoreversions -ignoreunavailable -noupgrade' -ArgList @('Install', '-Action', 'import', '-importfile', $importFile, '-ignoreunavailable', '-ignoreversions', '-noupgrade') `
    -Flags @(, @('import', "--import-file `"$importFile`"", '--ignore-unavailable', '--ignore-versions', '--no-upgrade')) -State { $z = Get-7Zip; [PSCustomObject]@{ Ok = ($z -and $z.Version -notlike "$old*"); Text = "7-Zip $($z.Version) (-ignoreversions => latest, not $old)" } }

Invoke-Test -Id 'F11' -Title 'Uninstall: by -name' -ArgList @('Uninstall', '-name', '7-Zip', '-silent') -Flags @(, @('--name "7-Zip"')) -NotFlags @(, $noPackageAgreement) -State $notInstalled

Invoke-Test -Id 'F12' -Title 'Install: EXE installer with -override' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-installertype', 'Exe', '-scope', 'Machine', '-override', '/S') `
    -Flags @(, @('--installer-type exe', '--override "/S"')) -State { $z = Get-7Zip; [PSCustomObject]@{ Ok = ($z -and -not $z.Msi); Text = "7-Zip $($z.Version) msi=$($z.Msi)" } }

Invoke-Test -Id 'F13' -Title 'Install: -proxy with a dummy proxy (informational, network is expected to fail)' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent', '-proxy', 'http://127.0.0.1:9') `
    -ExpectExit $null -Flags @(, @('--proxy http://127.0.0.1:9'))

Invoke-Test -Id 'F14' -Title 'Uninstall: -allversions + -OverrideAPPName (custom toolkit log name)' -ArgList @('Uninstall', '-id', '7zip.7zip', '-exact', '-silent', '-allversions', '-OverrideAPPName', 'WingetFW-Test') `
    -Flags @(, @('--all-versions')) -NotFlags @(, $noPackageAgreement) -State $notInstalled

# ---------------------------------------------------------------- portable package (rename / location / preserve / purge), Admin mode
Invoke-Test -Id 'P01' -Title 'Install: portable jq machine scope with -rename (name with space)' -ArgList @('Install', '-id', 'jqlang.jq', '-exact', '-silent', '-scope', 'Machine', '-rename', 'jq fw.exe') `
    -Flags @(, @('--rename "jq fw.exe"')) -State { $d = Get-JqMachineFolder; $ok = [Bool]($d -and (Test-Path (Join-Path $d.FullName 'jq fw.exe'))); [PSCustomObject]@{ Ok = $ok; Text = "'jq fw.exe' in $($d.FullName): $ok" } }
Invoke-Test -Id 'P02' -Title 'Uninstall: portable jq with -preserve (file created by the app stays)' -ArgList @('Uninstall', '-id', 'jqlang.jq', '-exact', '-silent', '-preserve') `
    -Pre { $d = Get-JqMachineFolder; Set-Content (Join-Path $d.FullName 'created-by-app.txt') 'test'; "created $($d.FullName)\created-by-app.txt" } `
    -Flags @(, @('--preserve')) -State { $f = Get-ChildItem 'C:\Program Files\WinGet\Packages' -Recurse -Filter 'created-by-app.txt' -ErrorAction SilentlyContinue; $exe = Get-ChildItem 'C:\Program Files\WinGet\Packages' -Recurse -Filter 'jq fw.exe' -ErrorAction SilentlyContinue; [PSCustomObject]@{ Ok = ([Bool]$f -and -not $exe); Text = "created-by-app.txt kept: $([Bool]$f), 'jq fw.exe' removed: $(-not $exe)" } }
Invoke-Test -Id 'P03' -Title 'Install: portable jq with -location (path with spaces)' -ArgList @('Install', '-id', 'jqlang.jq', '-exact', '-silent', '-scope', 'Machine', '-location', $jqLocation) `
    -Flags @(, @("--location `"$jqLocation`"")) -State { $ok = [Bool](Get-ChildItem $jqLocation -Filter '*.exe' -Recurse -ErrorAction SilentlyContinue); [PSCustomObject]@{ Ok = $ok; Text = "jq exe in $($jqLocation): $ok" } }
Invoke-Test -Id 'P04' -Title 'Uninstall: portable jq with -purge (all files removed)' -ArgList @('Uninstall', '-id', 'jqlang.jq', '-exact', '-silent', '-purge') `
    -Pre { Set-Content (Join-Path $jqLocation 'created-by-app.txt') 'test'; "created $jqLocation\created-by-app.txt" } `
    -Flags @(, @('--purge')) -State { $left = @(Get-ChildItem $jqLocation -Recurse -File -ErrorAction SilentlyContinue); [PSCustomObject]@{ Ok = ($left.Count -eq 0); Text = "files left in $($jqLocation): $($left.Count)" } }

# ---------------------------------------------------------------- settings: policy > command line > local key > config file > default (Admin mode)
# S01-S05 use dummy proxies (127.0.0.x:9), so winget is expected to fail; the tests check which proxy winget gets
Invoke-Test -Id 'S01' -Title 'Settings: policy Proxy beats -proxy on the command line (informational exit)' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent', '-proxy', 'http://127.0.0.3:9') `
    -Pre { Reset-WingetFWSettings; Set-WingetFWTestSetting Policy Proxy 'http://127.0.0.2:9' } -ExpectExit $null `
    -Flags @(, @('--proxy http://127.0.0.2:9')) -NotFlags @(, @('127.0.0.3')) -ExpectLog @('Setting \[Proxy\] = \[http://127\.0\.0\.2:9\] from \[Policy\]')
Invoke-Test -Id 'S02' -Title 'Settings: -proxy on the command line beats the local key (informational exit)' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent', '-proxy', 'http://127.0.0.3:9') `
    -Pre { Reset-WingetFWSettings; Set-WingetFWTestSetting Local Proxy 'http://127.0.0.4:9' } -ExpectExit $null `
    -Flags @(, @('--proxy http://127.0.0.3:9')) -NotFlags @(, @('127.0.0.4')) -ExpectLog @('Setting \[Proxy\] = \[http://127\.0\.0\.3:9\] from \[CommandLine\]')
Invoke-Test -Id 'S03' -Title 'Settings: local key Proxy beats the config file (informational exit)' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent') `
    -Pre { Reset-WingetFWSettings; Set-WingetFWTestSetting Local Proxy 'http://127.0.0.4:9'; Set-WingetFWTestConfig @{ Proxy = 'http://127.0.0.5:9' } } -ExpectExit $null `
    -Flags @(, @('--proxy http://127.0.0.4:9')) -NotFlags @(, @('127.0.0.5')) -ExpectLog @('Setting \[Proxy\] = \[http://127\.0\.0\.4:9\] from \[Local\]')
Invoke-Test -Id 'S04' -Title 'Settings: Proxy from the config file (informational exit)' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent') `
    -Pre { Reset-WingetFWSettings; Set-WingetFWTestConfig @{ Proxy = 'http://127.0.0.5:9' } } -ExpectExit $null `
    -Flags @(, @('--proxy http://127.0.0.5:9')) -ExpectLog @('Setting \[Proxy\] = \[http://127\.0\.0\.5:9\] from \[Config\]')
Invoke-Test -Id 'S05' -Title 'Settings: policy Proxy beats -noproxy (informational exit)' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent', '-noproxy') `
    -Pre { Reset-WingetFWSettings; Set-WingetFWTestSetting Policy Proxy 'http://127.0.0.2:9' } -ExpectExit $null `
    -Flags @(, @('--proxy http://127.0.0.2:9')) -NotFlags @(, @('--no-proxy')) -ExpectLog @('Ignoring -noproxy, Proxy is set by policy')
Invoke-Test -Id 'S06' -Title 'Settings: DefaultSilent (built-in default) adds --silent when no -silent/-interactive/-override is given' -ArgList @('Install', '-id', '7zip.7zip', '-exact') `
    -Pre { Reset-WingetFWSettings; 'no WingetFW settings' } -Flags @(, @('--silent')) -ExpectLog @('Adding -silent \(DefaultSilent from \[Default\]\)') -State $installed
Invoke-Test -Id 'S07' -Title 'Settings: policy DefaultSilent disabled - no --silent' -ArgList @('Install', '-id', '7zip.7zip', '-exact') `
    -Pre { Reset-WingetFWSettings; Set-WingetFWTestSetting Policy DefaultSilent 0 } -NotFlags @(, @('--silent')) -ExpectLog @('Setting \[DefaultSilent\] = \[False\] from \[Policy\]') -State $installed
Invoke-Test -Id 'S08' -Title 'Settings: policy DefaultSource is used for install without -source' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent') `
    -Pre { Reset-WingetFWSettings; Set-WingetFWTestSetting Policy DefaultSource 'winget' } -Flags @(, @('--source winget')) -ExpectLog @('Using source \[winget\] \(DefaultSource from \[Policy\]\)') -State $installed
Invoke-Test -Id 'S09' -Title 'Settings: DefaultSource is not used for uninstall' -ArgList @('Uninstall', '-id', '7zip.7zip', '-exact', '-silent') `
    -Pre { Reset-WingetFWSettings; Set-WingetFWTestSetting Policy DefaultSource 'winget' } -NotFlags @(, @('--source', '--accept-package-agreements')) -State $notInstalled
Invoke-Test -Id 'S10' -Title 'Settings: policy AllowedSources stops a source that is not in the list (60001)' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent', '-source', 'msstore') `
    -Pre { Reset-WingetFWSettings; Set-WingetFWTestSetting Policy AllowedSources @('winget') } -ExpectExit 60001 `
    -ExpectLog @('Source \[msstore\] is not allowed\. Allowed sources: winget \(AllowedSources from \[Policy\]\)') -ExpectNotLog @('Running winget Install')
Invoke-Test -Id 'S11' -Title 'Settings: policy Sources - a REST source that cannot be reached is logged as a warning, the install continues' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent') `
    -Pre { Reset-WingetFWSettings; Set-WingetFWTestSetting Policy Sources @{ WingetFWTest = 'https://127.0.0.1:9/api' } } `
    -ExpectLog @('winget source export --name WingetFWTest', 'winget source add --name WingetFWTest --arg https://127\.0\.0\.1:9/api --type Microsoft\.Rest', 'Could not add source \[WingetFWTest\]') `
    -Flags @(, @('--id 7zip.7zip')) -State $installed
Invoke-Test -Id 'S12' -Title 'Settings: policy TlsCheck enabled beats TlsCheck = $false in the config file' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent') `
    -Pre { Reset-WingetFWSettings; Set-WingetFWTestSetting Policy TlsCheck 1 } -ExpectLog @('Setting \[TlsCheck\] = \[True\] from \[Policy\]', 'SecurityProtocol is') -State $installed
Reset-WingetFWSettings

# ---------------------------------------------------------------- mod files (Admin mode unless noted)
$modsDir = Join-Path $pkgDir 'Mods'
$traceFile = Join-Path $Root 'mod-trace.txt'
$blobDir = Join-Path $Root 'blob'
$blobLog = Join-Path $Root 'blob-requests.txt'
$blobUrl = 'http://127.0.0.1:8085/mods/prod?sv=1&sp=rl&sig=SECRET'
Function Reset-WingetFWMods {
    Get-ChildItem $modsDir -Force | Where-Object { $_.Name -ne '_Template.ps1' } | Remove-Item -Recurse -Force
    Remove-Item $traceFile -Force -ErrorAction SilentlyContinue
}
# Each section writes "<label> <section> [exit code]" to the trace file
Function New-TraceMod([String]$Path, [String]$Label, [String[]]$Sections, [String]$Settings) {
    $lines = @()
    If ($Settings) { $lines += $Settings }
    ForEach ($s in $Sections) { $lines += 'function {0} {{ Add-Content -LiteralPath ''{1}'' -Value ("{2} {0} $($WingetFW.ExitCode)").TrimEnd() }}' -f $s, $traceFile, $Label }
    New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force | Out-Null
    Set-Content -Path $Path -Value $lines -Encoding UTF8
    "mod $Path ($($Sections -join ', '))"
}
Function Get-ModTrace { If (Test-Path $traceFile) { @(Get-Content $traceFile) } Else { @() } }
Function Set-TestMod([String]$Path, [String]$Content) {
    New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force | Out-Null
    Set-Content -Path $Path -Value $Content -Encoding UTF8
}
Function Test-ModTrace([String[]]$Expected) {
    $t = @(Get-ModTrace)
    $ok = $t.Count -eq $Expected.Count -and -not @(For ($i = 0; $i -lt $Expected.Count; $i++) { If ($t[$i] -notlike $Expected[$i]) { $i } }).Count
    [PSCustomObject]@{ Ok = $ok; Text = "mod trace: $($t -join ' > ') (expected: $($Expected -join ' > '))" }
}
$installSections = @('PreInstall', 'Install', 'PostInstall', 'NotInstalled')
$appMod = Join-Path $modsDir 'winget\7zip.7zip.ps1'
$globalMod = Join-Path $modsDir '_WingetFW.ps1'

$blobServer = @'
param($Root, $Prefix, $Log)
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($Prefix)
$listener.Start()
While ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response
    Add-Content -LiteralPath $Log -Value $request.RawUrl
    $path = [Uri]::UnescapeDataString($request.Url.AbsolutePath)
    If ($path -eq '/stop') { $response.Close(); $listener.Stop(); Break }
    If ($request.QueryString['comp'] -eq 'list') {
        $base = Join-Path $Root $path.Trim('/')
        $names = @(Get-ChildItem -LiteralPath $base -Recurse -File | ForEach-Object { $_.FullName.Substring($base.Length + 1).Replace('\', '/') } | Where-Object { $_.StartsWith([string]$request.QueryString['prefix']) })
        $bytes = [Text.Encoding]::UTF8.GetBytes('<?xml version="1.0" encoding="utf-8"?><EnumerationResults><Blobs>' + (($names | ForEach-Object { "<Blob><Name>$_</Name></Blob>" }) -join '') + '</Blobs><NextMarker /></EnumerationResults>')
        $response.ContentType = 'application/xml'
    }
    Else {
        $file = Join-Path $Root $path.TrimStart('/').Replace('/', '\')
        If (Test-Path -LiteralPath $file -PathType Leaf) { $bytes = [IO.File]::ReadAllBytes($file); $response.ContentType = 'application/octet-stream' }
        Else { $response.StatusCode = 404; $bytes = [Text.Encoding]::UTF8.GetBytes('not found') }
    }
    $response.OutputStream.Write($bytes, 0, $bytes.Length)
    $response.Close()
}
'@
Function Start-BlobServer {
    $script = Join-Path $tmpDir 'blob-server.ps1'
    Set-Content -Path $script -Value $blobServer -Encoding UTF8
    Remove-Item $blobLog -Force -ErrorAction SilentlyContinue
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -Root `"$blobDir`" -Prefix http://127.0.0.1:8085/ -Log `"$blobLog`"" -WindowStyle Hidden
    For ($i = 0; $i -lt 20; $i++) {
        Try { Invoke-WebRequest 'http://127.0.0.1:8085/ping' -UseBasicParsing -TimeoutSec 2 | Out-Null; Break }
        Catch { If ($_.Exception.Response) { Break }; Start-Sleep -Milliseconds 500 }
    }
    'blob server started on http://127.0.0.1:8085/ (folder ' + $blobDir + ')'
}
Function Stop-BlobServer { Try { Invoke-WebRequest 'http://127.0.0.1:8085/stop' -UseBasicParsing -TimeoutSec 5 | Out-Null } Catch { }; 'blob server stopped' }

# Test code signing certificate, trusted in LocalMachine Root and TrustedPublisher for the M07 test
$signCert = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=WingetFW Test Signing' -CertStoreLocation Cert:\LocalMachine\My -NotAfter (Get-Date).AddDays(2)
ForEach ($storeName in @('Root', 'TrustedPublisher')) {
    $store = New-Object Security.Cryptography.X509Certificates.X509Store($storeName, 'LocalMachine'); $store.Open('ReadWrite'); $store.Add($signCert); $store.Close()
}
Write-Result "  test signing certificate: $($signCert.Thumbprint)"
Remove-Item 'C:\ProgramData\WingetFW\Cache' -Recurse -Force -ErrorAction SilentlyContinue
Reset-WingetFWMods

Invoke-Test -Id 'M01' -Title 'Mods: global and app sections run in order around winget; $Settings.Install.Custom is used' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent') `
    -Pre { Reset-WingetFWSettings; Reset-WingetFWMods; New-TraceMod $globalMod 'global' $installSections; New-TraceMod $appMod 'app' $installSections '$Settings = @{ Install = @{ Custom = ''WINGETFW=1'' } }' } `
    -Flags @(, @('--custom "WINGETFW=1"')) -ExpectLog @('Using -custom .WINGETFW=1. from the mod file', 'Loaded Global mod', 'Loaded App mod') `
    -State { Test-ModTrace @('global PreInstall', 'app PreInstall', 'app Install *', 'global Install *', 'app PostInstall *', 'global PostInstall *') }
Invoke-Test -Id 'M02' -Title 'Mods: -custom on the command line beats $Settings in the mod file' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent', '-custom', 'CMD=1') `
    -Pre { Reset-WingetFWMods; New-TraceMod $appMod 'app' @('PreInstall') '$Settings = @{ Install = @{ Custom = ''WINGETFW=1'' } }' } `
    -Flags @(, @('--custom "CMD=1"')) -NotFlags @(, @('WINGETFW=1')) -ExpectLog @('-custom on the command line beats Custom in the mod file')
Invoke-Test -Id 'M03' -Title 'Mods: PreInstall returns $false - winget does not run, exit code 69002' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent') `
    -Pre { Reset-WingetFWMods; Set-TestMod $appMod 'function PreInstall { $false }'; 'app mod: PreInstall returns $false' } `
    -ExpectExit 69002 -ExpectLog @('returned \$false, skipping winget Install \(exit code 69002\)') -ExpectNotLog @('Running winget Install')
Invoke-Test -Id 'M04' -Title 'Mods: winget fails - During and NotInstalled run, PostInstall does not, the winget exit code is returned' -ArgList @('Install', '-id', 'WingetFW.DoesNotExist', '-exact', '-silent') `
    -Pre { Reset-WingetFWMods; New-TraceMod (Join-Path $modsDir 'winget\WingetFW.DoesNotExist.ps1') 'app' $installSections } `
    -ExpectExit @(-1978335212) -State { Test-ModTrace @('app PreInstall', 'app Install -1978335212', 'app NotInstalled -1978335212') }
Invoke-Test -Id 'M05' -Title 'Mods: a mod file with code at the top level is refused (60001)' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent') `
    -Pre { Reset-WingetFWMods; Set-TestMod $appMod "Write-Output 'runs at load'`nfunction PreInstall { }"; 'app mod with top-level code' } `
    -ExpectExit 60001 -ExpectLog @('runs code when the file is loaded') -ExpectNotLog @('Running winget Install')
Invoke-Test -Id 'M06' -Title 'Mods: RequireSignedScripts Signed refuses an unsigned mod file (60001)' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent') `
    -Pre { Reset-WingetFWMods; New-TraceMod $appMod 'app' @('PreInstall'); Set-WingetFWTestSetting Policy RequireSignedScripts 'Signed' } `
    -ExpectExit 60001 -ExpectLog @('is not validly signed \(NotSigned\)') -ExpectNotLog @('Running winget Install')
Invoke-Test -Id 'M07' -Title 'Mods: RequireSignedScripts TrustedSigners runs a mod file signed by a trusted signer' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent') `
    -Pre { Reset-WingetFWSettings; Reset-WingetFWMods; New-TraceMod $appMod 'app' @('PreInstall')
           $sig = Set-AuthenticodeSignature -FilePath $appMod -Certificate $signCert; "signed: $($sig.Status)"
           Set-WingetFWTestSetting Policy RequireSignedScripts 'TrustedSigners'; Set-WingetFWTestSetting Policy TrustedSigners @($signCert.Thumbprint) } `
    -ExpectLog @('is signed by \[CN=WingetFW Test Signing\]') -State { Test-ModTrace @('app PreInstall') }
Invoke-Test -Id 'M08' -Title 'Mods: a ScriptRoot that is not in AllowedScriptSources is refused (60001)' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent') `
    -Pre { Reset-WingetFWSettings; Reset-WingetFWMods; New-Item -ItemType Directory -Path (Join-Path $Root 'othermods') -Force | Out-Null; Set-WingetFWTestSetting Policy ScriptRoot @((Join-Path $Root 'othermods')) } `
    -ExpectExit 60001 -ExpectLog @('is not in AllowedScriptSources') -ExpectNotLog @('Running winget Install')
Invoke-Test -Id 'M09' -Title 'Mods: ScriptRoot on a UNC share (\\localhost\C$)' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent') `
    -Pre { Reset-WingetFWSettings; Reset-WingetFWMods; $unc = Join-Path $Root 'uncmods'; Remove-Item $unc -Recurse -Force -ErrorAction SilentlyContinue
           New-TraceMod (Join-Path $unc 'winget\7zip.7zip.ps1') 'unc' @('PreInstall')
           Set-WingetFWTestSetting Policy ScriptRoot @('\\localhost\C$\temp\wingetfw-vmtest\uncmods'); Set-WingetFWTestSetting Policy AllowedScriptSources @('\\localhost\C$\temp\wingetfw-vmtest\') } `
    -ExpectLog @('Loaded App mod \[\\\\localhost\\C\$\\temp\\wingetfw-vmtest\\uncmods\\winget\\7zip\.7zip\.ps1\]') -State { Test-ModTrace @('unc PreInstall') }
Invoke-Test -Id 'M10' -Title 'Mods: Azure blob ScriptRoot (simulated), OnDemand; the SAS is masked in the log' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent') `
    -Pre { Reset-WingetFWSettings; Reset-WingetFWMods; Remove-Item $blobDir -Recurse -Force -ErrorAction SilentlyContinue
           New-TraceMod (Join-Path $blobDir 'mods\prod\_WingetFW.ps1') 'blobglobal' @('PreInstall'); New-TraceMod (Join-Path $blobDir 'mods\prod\winget\7zip.7zip.ps1') 'blob' @('PreInstall')
           Start-BlobServer; Set-WingetFWTestSetting Policy ScriptRoot @($blobUrl); Set-WingetFWTestSetting Policy AllowedScriptSources @('http://127.0.0.1:8085/mods/') } `
    -ExpectLog @('Loaded App mod \[http://127\.0\.0\.1:8085/mods/prod/winget/7zip\.7zip\.ps1\?sv=1&sp=rl&sig=\*\*\*\]') -ExpectNotLog @('SECRET') `
    -State { Test-ModTrace @('blobglobal PreInstall', 'blob PreInstall') }
Invoke-Test -Id 'M11' -Title 'Mods: Azure blob ScriptRoot (simulated), Mirror lists the container and copies all mod files' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent') `
    -Pre { Remove-Item $traceFile -Force -ErrorAction SilentlyContinue; Set-WingetFWTestSetting Policy ScriptSyncMode 'Mirror' } `
    -ExpectLog @('Mirrored 2 mod file\(s\)') -ExpectNotLog @('SECRET') `
    -State { $listed = [Bool](Get-Content $blobLog | Where-Object { $_ -match 'comp=list' -and $_ -match 'sig=SECRET' }); $t = Test-ModTrace @('blobglobal PreInstall', 'blob PreInstall'); [PSCustomObject]@{ Ok = ($listed -and $t.Ok); Text = "container listed with SAS: $listed; $($t.Text)" } }
Invoke-Test -Id 'M12' -Title 'Mods: ScriptRoot cannot be reached and UseCachedScriptsWhenOffline is off (60001)' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent') `
    -Pre { Stop-BlobServer; Remove-Item $traceFile -Force -ErrorAction SilentlyContinue; Remove-ItemProperty -Path $policyKey -Name 'ScriptSyncMode' -ErrorAction SilentlyContinue; 'ScriptSyncMode OnDemand' } `
    -ExpectExit 60001 -ExpectLog @("can't be reached and UseCachedScriptsWhenOffline is off") -ExpectNotLog @('Running winget Install', 'SECRET')
Invoke-Test -Id 'M13' -Title 'Mods: ScriptRoot cannot be reached - UseCachedScriptsWhenOffline uses the cached copies' -ArgList @('Install', '-id', '7zip.7zip', '-exact', '-silent') `
    -Pre { Remove-Item $traceFile -Force -ErrorAction SilentlyContinue; Set-WingetFWTestSetting Policy UseCachedScriptsWhenOffline 1 } `
    -ExpectLog @('using the cached copy') -State { Test-ModTrace @('blobglobal PreInstall', 'blob PreInstall') }
Invoke-Test -Id 'M14' -Title 'Mods: user mode runs the global mod (NotUninstalled when jq is not installed for the user)' -Mode User -ArgList @('Uninstall', '-id', 'jqlang.jq', '-exact', '-silent', '-scope', 'User') `
    -Pre { Reset-WingetFWSettings; Reset-WingetFWMods; New-TraceMod $globalMod 'global' @('PreUninstall', 'PostUninstall', 'NotUninstalled') } `
    -ExpectExit @(-1978335212) -State { Test-ModTrace @('global PreUninstall', 'global NotUninstalled -1978335212') }
Reset-WingetFWSettings
Reset-WingetFWMods

# ---------------------------------------------------------------- User mode (current user, no PsExec)
Invoke-Test -Id 'U01' -Title 'User mode: install portable jq user scope' -Mode User -ArgList @('Install', '-id', 'jqlang.jq', '-exact', '-silent', '-scope', 'User') `
    -Flags @(, @('--scope user')) -State { $d = Get-JqUserFolder; [PSCustomObject]@{ Ok = [Bool]$d; Text = "user package folder: $($d.FullName)" } }
Invoke-Test -Id 'U02' -Title 'User mode: uninstall jq' -Mode User -ArgList @('Uninstall', '-id', 'jqlang.jq', '-exact', '-silent') `
    -NotFlags @(, $noPackageAgreement) -State { $d = Get-JqUserFolder; [PSCustomObject]@{ Ok = -not $d; Text = "user package folder removed: $(-not $d)" } }
Invoke-Test -Id 'U03' -Title 'User mode: install Postman (EXE installer, user scope)' -Mode User -ArgList @('Install', '-id', 'Postman.Postman', '-exact', '-silent', '-scope', 'User') `
    -Flags @(, @('--id Postman.Postman', '--scope user', '--silent')) -State { $p = Get-PostmanUser; [PSCustomObject]@{ Ok = [Bool]$p; Text = "Postman in HKCU uninstall: $([Bool]$p) $($p.DisplayVersion)" } }
# The Postman installer starts the app after install; a running Postman can block the uninstall
Invoke-Test -Id 'U04' -Title 'User mode: uninstall Postman' -Mode User -ArgList @('Uninstall', '-id', 'Postman.Postman', '-exact', '-silent') `
    -Pre { $p = @(Get-Process -Name 'Postman' -ErrorAction SilentlyContinue); $p | Stop-Process -Force; "stopped $($p.Count) Postman process(es)" } `
    -NotFlags @(, $noPackageAgreement) -State { $p = Get-PostmanUser; [PSCustomObject]@{ Ok = -not $p; Text = "Postman removed from HKCU uninstall: $(-not $p)" } }
# Simulates the first-logon race: App Installer is NonRemovable, so LOCALAPPDATA points to a folder where winget appears
# only after WingetFW has logged retry attempt 2 (a fixed delay failed when the registration call took longer)
$realLocalAppData = $env:LOCALAPPDATA
$fakeLocalAppData = Join-Path $Root 'first logon localappdata'
Invoke-Test -Id 'U05' -Title 'User mode: winget appears a few seconds late (first logon) - WingetFW registers App Installer, retries and installs jq' -Mode User -ArgList @('Install', '-id', 'jqlang.jq', '-exact', '-silent', '-scope', 'User') `
    -Pre { New-Item -ItemType Directory -Path "$fakeLocalAppData\Microsoft" -Force | Out-Null; $env:LOCALAPPDATA = $fakeLocalAppData
           $watch = "`$s = $((Get-Item $toolkitLog).Length); `$end = (Get-Date).AddSeconds(90); Do { Start-Sleep -Milliseconds 500; `$fs = [IO.File]::Open('$toolkitLog', 'Open', 'Read', 'ReadWrite'); `$fs.Position = `$s; `$t = (New-Object IO.StreamReader(`$fs)).ReadToEnd(); `$fs.Close() } Until ((`$t -match 'attempt 2 of 5') -or ((Get-Date) -gt `$end)); New-Item -ItemType Junction -Path '$fakeLocalAppData\Microsoft\WindowsApps' -Target '$realLocalAppData\Microsoft\WindowsApps' | Out-Null"
           Start-Process powershell.exe -ArgumentList "-NoProfile -EncodedCommand $([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($watch)))" -WindowStyle Hidden
           "LOCALAPPDATA=$fakeLocalAppData, Microsoft\WindowsApps is linked in after WingetFW logs retry attempt 2" } `
    -ExpectLog @('requesting App Installer registration', 'winget not found yet \(attempt 2 of 5\)') -Flags @(, @('--scope user')) `
    -State { $d = Get-ChildItem "$realLocalAppData\Microsoft\WinGet\Packages" -Directory -Filter 'jqlang.jq*' -ErrorAction SilentlyContinue | Select-Object -First 1; [PSCustomObject]@{ Ok = [Bool]$d; Text = "user package folder: $($d.FullName)" } }
$env:LOCALAPPDATA = $realLocalAppData
Remove-FakeLocalAppData
Invoke-Test -Id 'U06' -Title 'User mode: uninstall jq' -Mode User -ArgList @('Uninstall', '-id', 'jqlang.jq', '-exact', '-silent') `
    -NotFlags @(, $noPackageAgreement) -State { $d = Get-JqUserFolder; [PSCustomObject]@{ Ok = -not $d; Text = "user package folder removed: $(-not $d)" } }

# ---------------------------------------------------------------- teardown
Write-Result ''
Write-Result 'TEARDOWN'
$adminSettings | Where-Object { -not $before.adminSettings.$_ } | ForEach-Object { Invoke-WingetAsSystem "settings --disable $_" | Out-Null }
Reset-WingetFWSettings
Invoke-WingetAsSystem 'source remove --name WingetFWTest' | Out-Null
Stop-BlobServer | Out-Null
ForEach ($storeName in @('My', 'Root', 'TrustedPublisher')) {
    $store = New-Object Security.Cryptography.X509Certificates.X509Store($storeName, 'LocalMachine'); $store.Open('ReadWrite')
    @($store.Certificates | Where-Object { $_.Subject -eq 'CN=WingetFW Test Signing' }) | ForEach-Object { $store.Remove($_) }
    $store.Close()
}
Remove-Item $stateFile -Force -ErrorAction SilentlyContinue
Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Result ''
Write-Result ('=' * 110)
Write-Result 'SUMMARY'
$script:results | Select-Object Id, Result, ExitText, RunAs, Title | Format-Table -AutoSize | Out-String -Width 220 | ForEach-Object { Write-Result $_.TrimEnd() }
Write-Result "PASS $(@($script:results | Where-Object Result -eq 'PASS').Count) / $($script:results.Count)"

[PSCustomObject]@{
    RunDate = (Get-Date -Format 'yyyy-MM-dd HH:mm'); Computer = $env:COMPUTERNAME; Os = $osVersion; RunnerUser = $env:USERNAME
    WingetVersion = $wingetVersion; WingetPath = $wingetSystem; PackageVersion = $appVersion; PackageExe = $exeName; PsadtVersion = $psadtVersion; PsExec = $PsExecPath
    SevenZipLatest = $latest; SevenZipOlder = $old; AdminSettingsEnabled = @($adminSettings | Where-Object { -not $before.adminSettings.$_ })
    Tests = $script:results
} | ConvertTo-Json -Depth 6 | Set-Content $resultJson -Encoding UTF8
