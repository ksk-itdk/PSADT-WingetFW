#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.0.0' }

<#
.SYNOPSIS
    BETA - not fully tested, use at your own risk. Finds the WingetFW Win32 apps in Intune and updates them to a new WingetFW package.

.DESCRIPTION
    BETA: this script is not fully tested yet. Use it at your own risk, run -Apply with -WhatIf first
    and test it on a single app before updating more apps.

    Step 1 (-Export): connects to Intune (Microsoft Graph), finds all Win32 apps whose install command
    runs Deploy-Application.exe (WingetFW 3.x - 4.0.8) or Invoke-AppDeployToolkit.exe (WingetFW 5.0.0 or later)
    with a WingetFW package parameter, converts the install and uninstall command lines to the parameters
    of the new WingetFW version and writes everything to a CSV file. Deploy-Application.exe is replaced by
    Invoke-AppDeployToolkit.exe. Nothing is changed in Intune.

    Review the CSV. Set Update to No (or delete the row) for apps that must not be updated. The
    InstallCommandNew and UninstallCommandNew columns can be edited by hand.

    Step 2 (-Apply): reads the CSV and, for every row with Update = Yes, uploads the new WingetFW package
    (.intunewin) as a new content version of the existing app, sets the new command lines and writes
    "WingetFW <version>" to the app notes. Assignments, app ID and detection rules are kept.
    An app is skipped if its command lines were changed in Intune after the export.

    -ConvertCommandLine converts a single command line without connecting to Intune.

    The parameter conversion and the option rules are read from WingetFW-ParameterMap.psd1.

    Permissions: DeviceManagementApps.Read.All (Export) or DeviceManagementApps.ReadWrite.All (Apply),
    delegated for the interactive login, application permission for an app registration.

.PARAMETER Export
    Find the WingetFW apps and write the CSV file.

.PARAMETER Apply
    Update the apps marked Update = Yes in the CSV file.

.PARAMETER ConvertCommandLine
    Convert one WingetFW command line and show the result. No connection to Intune.

.PARAMETER CsvPath
    CSV file to write (Export) or read (Apply). Export default: .\WingetFW-IntuneApps-<date>.csv.

.PARAMETER IntuneWinFile
    The new WingetFW .intunewin file (setup file Invoke-AppDeployToolkit.exe).

.PARAMETER TargetVersion
    WingetFW version of the new package. Default: the newest AppVersion in ..\Toolkit\WinGetFW*\Invoke-AppDeployToolkit.ps1.

.PARAMETER TenantId
    Tenant ID or domain. Optional for the interactive login, required with -ClientId.

.PARAMETER ClientId
    Application (client) ID of an app registration. Without it an interactive login window is shown.

.PARAMETER ClientSecret
    Client secret of the app registration as SecureString, for example (Read-Host -AsSecureString).

.PARAMETER ParameterMapPath
    Path to WingetFW-ParameterMap.psd1. Default: next to this script.

.PARAMETER DetectionScriptPath
    Folder with the WingetFW detection scripts, used to report which detection script an app uses.
    Default: ..\Toolkit\Detection.

.EXAMPLE
    .\Update-WingetFWIntuneApps.ps1 -Export

    Interactive login, writes .\WingetFW-IntuneApps-<date>.csv.

.EXAMPLE
    .\Update-WingetFWIntuneApps.ps1 -Apply -CsvPath .\WingetFW-IntuneApps-20261011-1200.csv -IntuneWinFile .\Invoke-AppDeployToolkit.intunewin -WhatIf

    Shows what would be updated without changing anything.

.EXAMPLE
    $secret = Read-Host -AsSecureString -Prompt 'Client secret'
    .\Update-WingetFWIntuneApps.ps1 -Export -TenantId contoso.onmicrosoft.com -ClientId 00000000-0000-0000-0000-000000000000 -ClientSecret $secret

    Export with an app registration.

.EXAMPLE
    .\Update-WingetFWIntuneApps.ps1 -ConvertCommandLine 'Deploy-Application.exe -DeploymentType "Install" -WingetID "Postman.Postman" -WingetScope "--scope user" -Mode User'

.NOTES
    Maintained by: KSKITDK
    Version      : 0.4.0 (beta)

    Release notes
    0.4.0  - The conversion, the app list, the export rows and the update of one app moved to the WingetFW.Console
             module (Convert-WingetFWCommandLine, Get-WingetFWIntuneInventory, Update-WingetFWIntuneApp), so this
             script and the Console inventory give the same result. The CSV columns are unchanged.
           - A sign-in that ends without a Graph session (for example consent not given) stops with a clear
             message instead of "Connected to tenant  as app".
           - The detection script package ID is read from the $app line of the script, not from the example
             in its help (the 2.0.x templates have an example $app line).
           - -Apply -WhatIf writes the result CSV and removes the temporary package file (both were skipped).
           - -Apply commits the new content and sets the command lines, setup file and notes in two separate
             requests; in one request Intune committed the content but kept the old command lines and notes.
    0.3.0  - The Graph and upload functions moved to the WingetFW.Console module (..\Console\WingetFW.Console),
             which this script imports. Needs PowerShell 7.4 or later (was 7.0).
    0.2.0  - WingetFW 5.0.0 (PSAppDeployToolkit 4): Deploy-Application.exe is replaced by Invoke-AppDeployToolkit.exe,
             apps with Invoke-AppDeployToolkit.exe are found too, and the .intunewin setup file must be
             Invoke-AppDeployToolkit.exe.
           - -AllowRebootPassThru is removed (PSADT 4 passes reboot exit codes by default).
           - ServiceUI.exe in a command line is reported as an error (not in the 5.0.0 package).
           - The default target version is the newest AppVersion in ..\Toolkit\WinGetFW*.
           - The -Mode User / NonInteractive warning is removed (5.0.0 shows no error dialog).
    0.1.0  - First version (beta, not fully tested): export to CSV, apply from CSV, single command line conversion.

.LINK
    https://github.com/ksk-itdk/PSADT-WingetFW
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Export')]
Param (
    [Parameter(Mandatory = $true, ParameterSetName = 'Export')]
    [Switch]$Export,

    [Parameter(Mandatory = $true, ParameterSetName = 'Apply')]
    [Switch]$Apply,

    [Parameter(Mandatory = $true, ParameterSetName = 'Convert')]
    [String]$ConvertCommandLine,

    [Parameter(ParameterSetName = 'Export')]
    [Parameter(Mandatory = $true, ParameterSetName = 'Apply')]
    [String]$CsvPath,

    [Parameter(Mandatory = $true, ParameterSetName = 'Apply')]
    [String]$IntuneWinFile,

    [Parameter()]
    [String]$TargetVersion,

    [Parameter(ParameterSetName = 'Export')]
    [Parameter(ParameterSetName = 'Apply')]
    [String]$TenantId,

    [Parameter(ParameterSetName = 'Export')]
    [Parameter(ParameterSetName = 'Apply')]
    [String]$ClientId,

    [Parameter(ParameterSetName = 'Export')]
    [Parameter(ParameterSetName = 'Apply')]
    [SecureString]$ClientSecret,

    [Parameter()]
    [String]$ParameterMapPath = (Join-Path $PSScriptRoot 'WingetFW-ParameterMap.psd1'),

    [Parameter()]
    [String]$DetectionScriptPath = (Join-Path $PSScriptRoot '..\Toolkit\Detection')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Import-Module -Name (Join-Path $PSScriptRoot '..\Console\WingetFW.Console\WingetFW.Console.psd1') -Force

#region Helpers
Function Write-Status([String]$Message) {
    Write-Host "$(Get-Date -Format 'HH:mm:ss') $Message"
}

Function Get-TargetVersion {
    If ($TargetVersion) { Return $TargetVersion }
    $toolkit = Join-Path $PSScriptRoot '..\Toolkit'
    $versions = Get-ChildItem -LiteralPath $toolkit -Directory -Filter 'WinGetFW*' -ErrorAction SilentlyContinue | ForEach-Object {
        $v4 = Join-Path $_.FullName 'Invoke-AppDeployToolkit.ps1'
        $v3 = Join-Path $_.FullName 'Deploy-Application.ps1'
        If (Test-Path -LiteralPath $v4) { [regex]::Match((Get-Content -LiteralPath $v4 -Raw), "(?m)^\s*AppVersion = '([^']+)'").Groups[1].Value }
        ElseIf (Test-Path -LiteralPath $v3) { [regex]::Match((Get-Content -LiteralPath $v3 -Raw), "\`$appVersion = '([^']+)'").Groups[1].Value }
    } | Where-Object { $_ -as [version] } | Sort-Object { [version]$_ }
    If ($versions) { Return @($versions)[-1] }
    Throw "WingetFW version not found in $toolkit\WinGetFW*. Use -TargetVersion."
}
#endregion

#region Graph
Function Connect-Intune([String]$Scope) {
    If ($ClientId) {
        If (-not $TenantId -or -not $ClientSecret) { Throw '-ClientId requires -TenantId and -ClientSecret.' }
        Connect-MgGraph -TenantId $TenantId -ClientSecretCredential ([PSCredential]::new($ClientId, $ClientSecret)) -NoWelcome
    }
    Else {
        $connect = @{ Scopes = $Scope; NoWelcome = $true }
        If ($TenantId) { $connect.TenantId = $TenantId }
        Connect-MgGraph @connect
    }
    $context = Get-MgContext
    If (-not $context) { Throw "The sign-in did not complete (no Graph session). Sign in again in the browser window and consent to $Scope when asked." }
    Write-Status "Connected to tenant $($context.TenantId) as $(If ($context.Account) { $context.Account } Else { "app $($context.ClientId)" })"
    $accepted = @($Scope) + @(If ($Scope -like '*.Read.All') { $Scope -replace '\.Read\.All$', '.ReadWrite.All' })
    If (-not ($context.Scopes | Where-Object { $_ -in $accepted })) {
        $fix = If ($ClientId) { "Add $Scope as an APPLICATION permission to the app registration and grant admin consent." } Else { "Run Disconnect-MgGraph and try again, and consent to $Scope when asked." }
        Throw "The token does not have $($accepted -join ' or '). Permissions in the token: $($context.Scopes -join ', '). $fix"
    }
}
#endregion

$map = Import-PowerShellDataFile -LiteralPath $ParameterMapPath

If ($PSCmdlet.ParameterSetName -ne 'Convert') {
    Write-Warning 'BETA: Update-WingetFWIntuneApps.ps1 is not fully tested. Use it at your own risk; run -Apply with -WhatIf and on a single test app first.'
}

If ($PSCmdlet.ParameterSetName -eq 'Convert') {
    $conversion = Convert-WingetFWCommandLine -CommandLine $ConvertCommandLine -Map $map
    Return [PSCustomObject]@{
        Original        = $conversion.Original
        New             = $conversion.New
        DetectedVersion = $conversion.DetectedVersion
        Changes         = $conversion.Changes -join "`n"
        Warnings        = $conversion.Warnings -join "`n"
        Errors          = $conversion.Errors -join "`n"
    } | Format-List
}

$target = Get-TargetVersion

If ($Export) {
    If (-not $CsvPath) { $CsvPath = Join-Path (Get-Location) "WingetFW-IntuneApps-$(Get-Date -Format 'yyyyMMdd-HHmm').csv" }
    Connect-Intune 'DeviceManagementApps.Read.All'
    # Same rows as the Console inventory; Details is only shown in the Console
    $rows = @(Get-WingetFWIntuneInventory -TargetVersion $target -Map $map -DetectionScriptPath $DetectionScriptPath | Select-Object -Property * -ExcludeProperty Details)
    Write-Status "$($rows.Count) WingetFW apps found"
    $rows | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
    Write-Status "CSV written: $CsvPath"
    Write-Status "$(@($rows | Where-Object Update -eq 'Yes').Count) marked Update=Yes, $(@($rows | Where-Object Update -eq 'No').Count) marked Update=No (see the Errors column)"
}

If ($Apply) {
    $rows = @(Import-Csv -LiteralPath $CsvPath | Where-Object { $_.Update -eq 'Yes' })
    If (-not $rows) {
        Write-Status "No rows with Update = Yes in $CsvPath"
        Return
    }
    $package = Get-WingetFWIntuneWinPackage $IntuneWinFile
    Try {
        If ($package.SetupFile -ne $map.ExeName) { Throw "Setup file of $IntuneWinFile is '$($package.SetupFile)', expected $($map.ExeName)" }
        Connect-Intune 'DeviceManagementApps.ReadWrite.All'
        $results = ForEach ($row in $rows) {
            # Module functions do not see this script's -WhatIf, so it is passed on
            $status = Update-WingetFWIntuneApp -Row $row -Package $package -IntuneWinFile $IntuneWinFile -TargetVersion $target -Map $map -WhatIf:$WhatIfPreference
            Write-Status "$($row.DisplayName): $status"
            $row | Select-Object *, @{ n = 'Result'; e = { $status } }
        }
        $resultPath = Join-Path ([IO.Path]::GetDirectoryName((Resolve-Path -LiteralPath $CsvPath).Path)) ("{0}-result.csv" -f [IO.Path]::GetFileNameWithoutExtension($CsvPath))
        $results | Export-Csv -LiteralPath $resultPath -NoTypeInformation -Encoding UTF8 -WhatIf:$false
        Write-Status "Result written: $resultPath"
    }
    Finally {
        Remove-Item -LiteralPath $package.EncryptedFile -Force -ErrorAction SilentlyContinue -WhatIf:$false
    }
}
