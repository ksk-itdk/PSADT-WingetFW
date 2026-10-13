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
    Folder on the VM that contains the WinGetFW package folder. Must not be in a user profile
    (SYSTEM must be able to read it).

.PARAMETER PsExecPath
    Path to PsExec64.exe on the VM.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\temp\wingetfw-vmtest\Invoke-WingetFWTestSuite.ps1

.NOTES
    Maintained by: KSKITDK
    Version      : 1.2.1

    Release notes
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
    [String]$PsExecPath = 'C:\temp\PSTools\PsExec64.exe'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$pkgDir        = Join-Path $Root 'WinGetFW'
$exe           = Join-Path $pkgDir 'Deploy-Application.exe'
$resultDir     = Join-Path $Root 'results'
$tmpDir        = Join-Path $Root 'tmp'
$spaceDir      = Join-Path $Root 'path with spaces'
$resultLog     = Join-Path $resultDir 'WingetFW-TestResults.log'
$resultJson    = Join-Path $resultDir 'WingetFW-TestResults.json'
$toolkitLogDir = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
$appVersion    = ([regex]::Match((Get-Content (Join-Path $pkgDir 'Deploy-Application.ps1') -Raw), "\`$appVersion = '([^']+)'")).Groups[1].Value

If (-not (Test-Path $exe)) { Throw "Deploy-Application.exe not found: $exe" }
If (-not (Test-Path $PsExecPath)) { Throw "PsExec not found: $PsExecPath" }
If (Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'Deploy-Application' }) { Throw 'Another Deploy-Application run is active on this VM - aborting.' }
New-Item -ItemType Directory -Path $resultDir, $tmpDir, $spaceDir, $toolkitLogDir -Force | Out-Null
Remove-Item (Join-Path $resultDir '*'), (Join-Path $tmpDir '*'), (Join-Path $spaceDir '*') -Force -Recurse -ErrorAction SilentlyContinue

Function Write-Result([String]$Text) { Add-Content -Path $resultLog -Value $Text -Encoding UTF8; Write-Output $Text }

# Deploy-Application.exe (PSADT v3) strips double quotes and runs the args through -Command, so values with
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
    $executes = @($entries | Where-Object { $_.Component -eq 'Execute-Process' } | ForEach-Object { If ($_.Message -match ':: Executing \[.*?winget\.exe (.*)\]\.\.\.$') { $Matches[1].Trim() } })

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
    $excerpt = @($entries | Where-Object { $_.Component -in @('WingetFW-Test', 'Start-WinGetPackageFM', 'Execute-Process', 'Exit-Script') -or $_.Type -ge 2 } |
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
Write-Result "Package       : $exe"
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

# ---------------------------------------------------------------- Deploy-Application.exe quoting (known PSADT v3 behaviour)
Invoke-Test -Id 'Q01' -Title 'Deploy-Application.exe: double-quoted value with spaces is split - script does not start, exit 0' -ArgList @('Install', '-id', '7zip.7zip', '-name', '7 Zip') `
    -RawArgs '-DeploymentType Install -id 7zip.7zip -name "7 Zip" -DeployMode Silent' -ExpectExit 0 -ExpectNotLog @('Start-WinGetPackageFM', 'cannot be used together', 'Installation completed')
Invoke-Test -Id 'Q02' -Title "Deploy-Application.exe: single-quoted value with spaces is passed correctly" -ArgList @('Install', '-id', '7zip.7zip', '-name', '7 Zip') `
    -RawArgs "-DeploymentType Install -id 7zip.7zip -name '7 Zip' -DeployMode Silent" -ExpectExit 60001 -ExpectLog @('cannot be used together\. Use only one of -wingetmanifest, -id, -name, -moniker')
Invoke-Test -Id 'Q03' -Title 'Deploy-Application.exe: unquoted {GUID} loses its braces (PowerShell script block)' -ArgList @('Uninstall', '-productcode', '{00000000-0000-0000-0000-000000000000}') `
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
Remove-Item $stateFile -Force -ErrorAction SilentlyContinue
Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Result ''
Write-Result ('=' * 110)
Write-Result 'SUMMARY'
$script:results | Select-Object Id, Result, ExitText, RunAs, Title | Format-Table -AutoSize | Out-String -Width 220 | ForEach-Object { Write-Result $_.TrimEnd() }
Write-Result "PASS $(@($script:results | Where-Object Result -eq 'PASS').Count) / $($script:results.Count)"

[PSCustomObject]@{
    RunDate = (Get-Date -Format 'yyyy-MM-dd HH:mm'); Computer = $env:COMPUTERNAME; Os = $osVersion; RunnerUser = $env:USERNAME
    WingetVersion = $wingetVersion; WingetPath = $wingetSystem; PackageVersion = $appVersion; PsExec = $PsExecPath
    SevenZipLatest = $latest; SevenZipOlder = $old; AdminSettingsEnabled = @($adminSettings | Where-Object { -not $before.adminSettings.$_ })
    Tests = $script:results
} | ConvertTo-Json -Depth 6 | Set-Content $resultJson -Encoding UTF8
