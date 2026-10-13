#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.0.0' }

<#
.SYNOPSIS
    BETA - not fully tested, use at your own risk. Finds the WingetFW Win32 apps in Intune and updates them to a new WingetFW package.

.DESCRIPTION
    BETA: this script is not fully tested yet. Use it at your own risk, run -Apply with -WhatIf first
    and test it on a single app before updating more apps.

    Step 1 (-Export): connects to Intune (Microsoft Graph), finds all Win32 apps whose install command
    runs Deploy-Application.exe with a WingetFW package parameter, converts the install and uninstall
    command lines to the parameters of the new WingetFW version and writes everything to a CSV file.
    Nothing is changed in Intune.

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
    Convert one Deploy-Application.exe command line and show the result. No connection to Intune.

.PARAMETER CsvPath
    CSV file to write (Export) or read (Apply). Export default: .\WingetFW-IntuneApps-<date>.csv.

.PARAMETER IntuneWinFile
    The new WingetFW .intunewin file (setup file Deploy-Application.exe).

.PARAMETER TargetVersion
    WingetFW version of the new package. Default: $appVersion from ..\Toolkit\WinGetFW\Deploy-Application.ps1.

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
    .\Update-WingetFWIntuneApps.ps1 -Apply -CsvPath .\WingetFW-IntuneApps-20261011-1200.csv -IntuneWinFile .\Deploy-Application.intunewin -WhatIf

    Shows what would be updated without changing anything.

.EXAMPLE
    $secret = Read-Host -AsSecureString -Prompt 'Client secret'
    .\Update-WingetFWIntuneApps.ps1 -Export -TenantId contoso.onmicrosoft.com -ClientId 00000000-0000-0000-0000-000000000000 -ClientSecret $secret

    Export with an app registration.

.EXAMPLE
    .\Update-WingetFWIntuneApps.ps1 -ConvertCommandLine 'Deploy-Application.exe -DeploymentType "Install" -WingetID "Postman.Postman" -WingetScope "--scope user" -Mode User'

.NOTES
    Maintained by: KSKITDK
    Version      : 0.1.0 (beta)

    Release notes
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
$graphBase = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'

#region Conversion
Function Get-MapName([Hashtable]$Table, [String]$Name) {
    # Returns the key with its original casing, $null if not found
    ForEach ($key in $Table.Keys) { If ($key -ieq $Name) { Return $key } }
    Return $null
}

Function Get-AstValue($Ast) {
    Switch ($Ast.GetType().Name) {
        'StringConstantExpressionAst' { Return $Ast.Value }
        'ExpandableStringExpressionAst' { Return $Ast.Value }
        'ConstantExpressionAst' { Return [String]$Ast.Value }
        # Unquoted {GUID}
        default { Return $Ast.Extent.Text }
    }
}

Function Format-Argument($Item) {
    If ($Item.IsSwitch) {
        If ($Item.SwitchArgument) { Return "-$($Item.Name):$($Item.SwitchArgument)" }
        Return "-$($Item.Name)"
    }
    Return "-$($Item.Name) '$(([String]$Item.Value) -replace "'", "''")'"
}

Function ConvertFrom-WingetText([String]$Text, [Hashtable]$Map, $Result) {
    # Splits raw winget arguments (3.x -WingetCM / -WingetScope) into WingetFW parameters
    $tokens = @([regex]::Matches($Text, '"[^"]*"|''[^'']*''|\S+') | ForEach-Object { $_.Value })
    $items = @()
    $i = 0
    While ($i -lt $tokens.Count) {
        $token = $tokens[$i]
        $key = Get-MapName $Map.WingetOptions $token
        If (-not $key) {
            $Result.Errors.Add("Unknown winget argument '$token' in '$Text'")
            $i++            # Skip the value of the unknown option
            While ($i -lt $tokens.Count -and -not (Get-MapName $Map.WingetOptions $tokens[$i]) -and $tokens[$i] -notmatch '^-') { $i++ }            Continue
        }
        $option = $Map.WingetOptions[$key]
        $value = $null
        If ($option.Value) {
            # Values with spaces were often not quoted in 3.x, so take everything up to the next winget option
            $parts = @()
            $i++
            While ($i -lt $tokens.Count -and -not (Get-MapName $Map.WingetOptions $tokens[$i])) {
                $parts += $tokens[$i].Trim('"').Trim("'")
                $i++
            }
            If ($parts.Count -eq 0) {
                $Result.Errors.Add("winget argument '$token' has no value in '$Text'")
                Continue
            }
            $value = $parts -join ' '
        }
        Else {
            $i++
        }
        If (-not $option.Parameter) {
            $Result.Changes.Add("'$token' dropped (WingetFW adds it itself)")
            Continue
        }
        If ($option.Parameter -eq 'scope') { $value = (Get-Culture).TextInfo.ToTitleCase($value.ToLower()) }
        $items += [PSCustomObject]@{ Name = $option.Parameter; Value = $value; IsSwitch = -not $option.Value; SwitchArgument = $null; FromOld = $true }
    }
    Return $items
}

Function Convert-WingetFWCommandLine {
    Param (
        [Parameter()]
        [String]$CommandLine,

        [Parameter()]
        [Hashtable]$Map,

        # WingetFW version from the app notes, if known
        [Parameter()]
        [String]$KnownVersion
    )

    $result = [PSCustomObject]@{
        Original        = $CommandLine
        New             = $CommandLine
        DetectedVersion = ''
        Package         = ''
        Changes         = [System.Collections.Generic.List[String]]::new()
        Warnings        = [System.Collections.Generic.List[String]]::new()
        Errors          = [System.Collections.Generic.List[String]]::new()
    }
    If ([String]::IsNullOrWhiteSpace($CommandLine)) { Return $result }

    $match = [regex]::Match($CommandLine, '(?i)"?Deploy-Application(\.exe)?"?')
    If (-not $match.Success) {
        $result.Errors.Add('Deploy-Application.exe not found in the command line')
        Return $result
    }
    # Text before the exe (for example ServiceUI.exe -process:explorer.exe) is kept as it is
    $prefix = $CommandLine.Substring(0, $match.Index)
    $exe = $match.Value
    $argText = $CommandLine.Substring($match.Index + $match.Length)

    # Deploy-Application.exe passes the arguments to powershell.exe -Command, so the PowerShell parser reads them the same way
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput("x $argText", [ref]$null, [ref]$parseErrors)
    If ($parseErrors) {
        $result.Errors.Add("Command line could not be parsed: $($parseErrors[0].Message)")
        Return $result
    }
    $command = $ast.Find({ Param($a) $a -is [System.Management.Automation.Language.CommandAst] }, $true)
    $elements = @($command.CommandElements | Select-Object -Skip 1)

    $items = @()
    For ($i = 0; $i -lt $elements.Count; $i++) {
        $element = $elements[$i]
        If ($element -isnot [System.Management.Automation.Language.CommandParameterAst]) {
            $result.Errors.Add("Value without parameter name: $($element.Extent.Text)")
            Continue
        }
        $name = Get-MapName $Map.Parameters $element.ParameterName
        $type = If ($name) { $Map.Parameters[$name] } Else { $name = Get-MapName $Map.OldParameters $element.ParameterName; If ($name) { $Map.OldParameters[$name] } }
        If (-not $name) {
            $result.Errors.Add("Unknown parameter -$($element.ParameterName)")
            $name = $element.ParameterName
            $type = 'String'
        }
        $item = [PSCustomObject]@{ Name = $name; Value = $null; IsSwitch = ($type -eq 'Switch'); SwitchArgument = $null; FromOld = $false }
        If ($element.Argument) {
            If ($item.IsSwitch) { $item.SwitchArgument = $element.Argument.Extent.Text } Else { $item.Value = Get-AstValue $element.Argument }
        }
        ElseIf (-not $item.IsSwitch) {
            If ($i + 1 -lt $elements.Count -and $elements[$i + 1] -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                $i++
                $item.Value = Get-AstValue $elements[$i]
            }
            Else {
                $result.Errors.Add("Parameter -$name has no value")
            }
        }
        $items += $item
    }

    $names = @($items | ForEach-Object { $_.Name })
    $isV3 = [Bool]($names | Where-Object { $_ -in $Map.V3Parameters })
    $isOld4 = [Bool]($names | Where-Object { $_ -in @('testverbose', 'wait') }) -or [Bool]($items | Where-Object { $_.Name -eq 'scope' -and $_.Value -in $Map.RemovedScopeValues })
    $isNew4 = [Bool]($names | Where-Object { $_ -in $Map.V407Parameters })
    $result.DetectedVersion = If ($KnownVersion) { $KnownVersion } ElseIf ($isV3) { '3.x' } ElseIf ($isOld4) { '4.0.0 - 4.0.6' } ElseIf ($isNew4) { '4.0.7 or later' } Else { '4.x' }

    # Convert old parameters
    $converted = @()
    ForEach ($item in $items) {
        If ($Map.RenamedParameters.ContainsKey($item.Name)) {
            $newName = $Map.RenamedParameters[$item.Name]
            $result.Changes.Add("-$($item.Name) renamed to -$newName")
            $item.Name = $newName
            $item.FromOld = $true
            $converted += $item
        }
        ElseIf ($Map.RemovedParameters.ContainsKey($item.Name)) {
            $result.Changes.Add("-$($item.Name) removed: $($Map.RemovedParameters[$item.Name])")
        }
        ElseIf ($item.Name -in $Map.WingetTextParameters) {
            $newItems = @(ConvertFrom-WingetText -Text $item.Value -Map $Map -Result $result)
            $result.Changes.Add("-$($item.Name) '$($item.Value)' converted to: $(($newItems | ForEach-Object { Format-Argument $_ }) -join ' ')")
            $converted += $newItems
        }
        ElseIf ($item.Name -eq 'scope' -and $item.Value -in $Map.RemovedScopeValues) {
            $result.Changes.Add("-scope '$($item.Value)' removed (no longer supported; it was not passed to winget)")
        }
        Else {
            $converted += $item
        }
    }

    # The same parameter twice (for example -WingetScope and --scope in -WingetCM): keep the first
    $unique = @()
    ForEach ($item in $converted) {
        If ($unique | Where-Object { $_.Name -eq $item.Name }) {
            $result.Warnings.Add("-$($item.Name) was set more than once; the first value is kept")
            Continue
        }
        $unique += $item
    }
    $converted = $unique

    $get = { Param($n) $converted | Where-Object { $_.Name -eq $n -and (-not $_.IsSwitch -or $_.SwitchArgument -notmatch '\$false') } | Select-Object -First 1 }
    $deploymentType = If (& $get 'DeploymentType') { (& $get 'DeploymentType').Value } Else { 'Install' }

    # 3.x always ran winget with --silent
    $deploymentAction = If (& $get 'Action') { (& $get 'Action').Value } Else { $deploymentType }
    $overrideKept = (& $get 'override') -and $Map.ActionOptions[$deploymentAction.ToLower()] -contains 'override'
    If ($isV3 -and -not (& $get 'silent')) {
        If ($overrideKept) { $result.Changes.Add('-silent not added: 3.x sent --silent, but -override cannot be combined with -silent') }
        ElseIf (& $get 'interactive') { $result.Changes.Add('-silent not added because -interactive is used') }
        Else {
            $converted += [PSCustomObject]@{ Name = 'silent'; Value = $null; IsSwitch = $true; SwitchArgument = $null; FromOld = $true }
            $result.Changes.Add('-silent added (3.x always ran winget with --silent)')
        }
    }

    # Before 4.0.7 Repair always uninstalled and installed again
    $knownNew = $false
    If ($KnownVersion) { Try { $knownNew = [version]$KnownVersion -ge [version]'4.0.7' } Catch { $knownNew = $false } }
    If ($deploymentType -ieq 'Repair' -and -not $isNew4 -and -not $knownNew -and -not (& $get $Map.OldRepairParameter)) {
        $converted += [PSCustomObject]@{ Name = $Map.OldRepairParameter; Value = $null; IsSwitch = $true; SwitchArgument = $null; FromOld = $true }
        $result.Changes.Add("-$($Map.OldRepairParameter) added (Repair before 4.0.7 always uninstalled and installed again)")
    }

    # Validate against the rules of the new version
    $forceRepair = [Bool](& $get 'ForceRepair')
    $action = If (& $get 'Action') { (& $get 'Action').Value } Else { $deploymentType }
    If ($forceRepair) {
        If ($deploymentType -ieq 'Repair') { $action = 'install' } Else { $result.Warnings.Add('-ForceRepair is ignored unless -DeploymentType is Repair') }
    }
    $action = $action.ToLower()
    $allowed = $Map.ActionOptions[$action]
    If (-not $allowed) {
        $result.Errors.Add("Unknown action '$action'")
        $allowed = @()
    }
    $used = @($converted | Where-Object { $_.Name -notin $Map.FrameworkParameters -and $_.Name -in $Map.Parameters.Keys -and (-not $_.IsSwitch -or $_.SwitchArgument -notmatch '\$false') })
    $kept = @()
    ForEach ($item in $converted) {
        If ($item -in $used -and $item.Name -notin $allowed) {
            If ($item.FromOld) {
                # Older versions passed it to winget anyway, where it had no effect or failed
                $result.Changes.Add("-$($item.Name) removed: winget $action does not support it")
                Continue
            }
            $result.Errors.Add("-$($item.Name) is not supported with winget $action")
        }
        $kept += $item
    }
    $converted = $kept
    $usedNames = @($converted | Where-Object { $_ -in $used } | ForEach-Object { $_.Name })
    ForEach ($group in $Map.ConflictGroups) {
        $conflict = @($usedNames | Where-Object { $_ -in $group })
        If ($conflict.Count -gt 1) { $result.Errors.Add("-$($conflict -join ' and -') cannot be used together") }
    }
    ForEach ($key in $Map.Requires.Keys) {
        If ($key -in $usedNames -and $Map.Requires[$key] -notin $usedNames) { $result.Errors.Add("-$key requires -$($Map.Requires[$key])") }
    }
    $package = @($converted | Where-Object { $_.Name -in $Map.PackageParameters -and $_.Value } | Select-Object -First 1)
    If ($package) { $result.Package = $package[0].Value } Else { $result.Errors.Add('No package parameter (id, name, moniker, wingetmanifest, productcode or importfile)') }
    $mode = & $get 'Mode'
    $deployMode = & $get 'DeployMode'
    If ($mode -and $mode.Value -ieq 'User' -and (-not $deployMode -or $deployMode.Value -ine 'NonInteractive')) {
        $result.Warnings.Add("-Mode User without -DeployMode 'NonInteractive': an error shows a dialog that waits up to 6900 seconds")
    }

    $result.New = ("$prefix$exe " + (($converted | ForEach-Object { Format-Argument $_ }) -join ' ')).TrimEnd()
    If ($result.New -ne $CommandLine -and $result.Changes.Count -eq 0) { $result.Changes.Add('Values written in single quotes (Deploy-Application.exe removes double quotes)') }
    Return $result
}
#endregion

#region Helpers
Function Write-Status([String]$Message) {
    Write-Host "$(Get-Date -Format 'HH:mm:ss') $Message"
}

Function Get-TargetVersion {
    If ($TargetVersion) { Return $TargetVersion }
    $deployScript = Join-Path $PSScriptRoot '..\Toolkit\WinGetFW\Deploy-Application.ps1'
    If (Test-Path -LiteralPath $deployScript) {
        $version = [regex]::Match((Get-Content -LiteralPath $deployScript -Raw), "\`$appVersion = '([^']+)'").Groups[1].Value
        If ($version) { Return $version }
    }
    Throw "WingetFW version not found in $deployScript. Use -TargetVersion."
}

Function Get-NotesVersion([String]$Notes) {
    Return [regex]::Match([String]$Notes, 'WingetFW (\d+\.\d+\.\d+)').Groups[1].Value
}

Function Set-NotesVersion([String]$Notes, [String]$Version) {
    If ($Notes -match 'WingetFW \d+\.\d+\.\d+') { Return [regex]::Replace($Notes, 'WingetFW \d+\.\d+\.\d+', "WingetFW $Version") }
    If ([String]::IsNullOrWhiteSpace($Notes)) { Return "WingetFW $Version" }
    Return "$Notes`nWingetFW $Version"
}

Function Get-NormalizedScriptHash([String]$Text) {
    # App-specific lines ($app = "...", $AppName/$AppVersion) are ignored, so the same script version matches for every app
    $lines = $Text -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^\$(app|AppName|AppVersion)\s*=' }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    Return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

Function Get-KnownDetectionScripts {
    $known = @{}
    If (Test-Path -LiteralPath $DetectionScriptPath) {
        Get-ChildItem -LiteralPath $DetectionScriptPath -Filter '*.ps1' | ForEach-Object { $known[(Get-NormalizedScriptHash (Get-Content -LiteralPath $_.FullName -Raw))] = $_.BaseName }
    }
    Return $known
}

Function Get-DetectionInfo($App, [Hashtable]$KnownScripts) {
    $rules = @($App.rules | Where-Object { $_.ruleType -eq 'detection' }) + @($App.detectionRules)
    $rules = @($rules | Where-Object { $_ })
    If (-not $rules) { Return [PSCustomObject]@{ Rule = 'None'; AppId = '' } }
    $script = $rules | Where-Object { $_.'@odata.type' -match 'PowerShellScript' } | Select-Object -First 1
    If (-not $script) { Return [PSCustomObject]@{ Rule = (($rules | ForEach-Object { $_.'@odata.type' -replace '#microsoft.graph.win32LobApp', '' -replace 'Rule$|Detection$', '' }) -join ', '); AppId = '' } }
    $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($script.scriptContent)).TrimStart([char]0xFEFF)
    $name = $KnownScripts[(Get-NormalizedScriptHash $text)]
    Return [PSCustomObject]@{
        Rule  = If ($name) { "Script $name" } Else { 'Script (custom)' }
        AppId = [regex]::Match($text, '(?m)^\s*\$app\s*=\s*["'']([^"'']+)["'']').Groups[1].Value
    }
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
    Write-Status "Connected to tenant $($context.TenantId) as $(If ($context.Account) { $context.Account } Else { "app $($context.ClientId)" })"
    $accepted = @($Scope) + @(If ($Scope -like '*.Read.All') { $Scope -replace '\.Read\.All$', '.ReadWrite.All' })
    If (-not ($context.Scopes | Where-Object { $_ -in $accepted })) {
        $fix = If ($ClientId) { "Add $Scope as an APPLICATION permission to the app registration and grant admin consent." } Else { "Run Disconnect-MgGraph and try again, and consent to $Scope when asked." }
        Throw "The token does not have $($accepted -join ' or '). Permissions in the token: $($context.Scopes -join ', '). $fix"
    }
}

Function Invoke-Graph([String]$Method, [String]$Uri, $Body) {
    $request = @{ Method = $Method; Uri = $Uri; OutputType = 'PSObject' }
    If ($null -ne $Body) {
        $request.Body = $Body | ConvertTo-Json -Depth 10
        $request.ContentType = 'application/json'
    }
    Return Invoke-MgGraphRequest @request
}

Function Get-WingetFWApps {
    $uri = "$graphBase`?`$filter=isof('microsoft.graph.win32LobApp')"
    $apps = @()
    Do {
        Try {
            $page = Invoke-Graph GET $uri
        }
        Catch {
            If ($_.Exception.Message -match 'Forbidden|403') {
                $fix = If ($ClientId) { "The app registration $ClientId needs DeviceManagementApps.Read.All as an application permission with admin consent." } Else { "The account $((Get-MgContext).Account) needs an Intune role that can read apps, for example Intune Administrator or Application Manager (activate it first if it is a PIM role)." }
                Throw "Intune refused the request (Forbidden). $fix Details: $($_.Exception.Message)"
            }
            Throw
        }
        $apps += @($page.value)
        $uri = $page.'@odata.nextLink'
    } While ($uri)
    Write-Status "$($apps.Count) Win32 apps in Intune"
    $pattern = '(?i)(^|\s)-(' + (@($map.PackageParameters) + @($map.V3Parameters | Where-Object { $_ -eq 'WingetID' }) -join '|') + ')\b'
    Return @($apps | Where-Object { $_.installCommandLine -match '(?i)Deploy-Application' -and $_.installCommandLine -match $pattern })
}

Function Get-IntuneWinPackage([String]$Path) {
    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    Try {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq 'IntuneWinPackage/Metadata/Detection.xml' }
        If (-not $entry) { Throw "$Path is not a .intunewin file (Detection.xml missing)" }
        $reader = [IO.StreamReader]::new($entry.Open())
        [Xml]$detection = $reader.ReadToEnd()
        $reader.Close()
        $info = $detection.ApplicationInfo
        $content = $zip.Entries | Where-Object { $_.FullName -eq "IntuneWinPackage/Contents/$($info.FileName)" }
        $encryptedFile = Join-Path ([IO.Path]::GetTempPath()) ("WingetFW-{0}.bin" -f [guid]::NewGuid().ToString('N'))
        [IO.Compression.ZipFileExtensions]::ExtractToFile($content, $encryptedFile, $true)
        Return [PSCustomObject]@{
            FileName         = $info.FileName
            SetupFile        = $info.SetupFile
            UnencryptedSize  = [Int64]$info.UnencryptedContentSize
            EncryptedFile    = $encryptedFile
            EncryptedSize    = (Get-Item -LiteralPath $encryptedFile).Length
            EncryptionInfo   = @{
                encryptionKey        = $info.EncryptionInfo.EncryptionKey
                macKey               = $info.EncryptionInfo.MacKey
                initializationVector = $info.EncryptionInfo.InitializationVector
                mac                  = $info.EncryptionInfo.Mac
                profileIdentifier    = $info.EncryptionInfo.ProfileIdentifier
                fileDigest           = $info.EncryptionInfo.FileDigest
                fileDigestAlgorithm  = $info.EncryptionInfo.FileDigestAlgorithm
            }
        }
    }
    Finally {
        $zip.Dispose()
    }
}

Function Wait-ContentFile([String]$Uri, [String]$Stage) {
    For ($i = 0; $i -lt 60; $i++) {
        $file = Invoke-Graph GET $Uri
        If ($file.uploadState -eq "${Stage}Success") { Return $file }
        If ($file.uploadState -match "^${Stage}(Failed|TimedOut)$") { Throw "Content file state $($file.uploadState)" }
        Start-Sleep -Seconds 5
    }
    Throw "Content file did not reach ${Stage}Success within 5 minutes (state $($file.uploadState))"
}

Function Send-AzureBlob([String]$SasUri, [String]$Path) {
    $chunkSize = 6MB
    $blockIds = @()
    $stream = [IO.File]::OpenRead($Path)
    Try {
        $buffer = [Byte[]]::new($chunkSize)
        While (($read = $stream.Read($buffer, 0, $chunkSize)) -gt 0) {
            $chunk = [Byte[]]::new($read)
            [Array]::Copy($buffer, $chunk, $read)
            $blockId = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($blockIds.Count.ToString('0000')))
            Invoke-WebRequest -Method Put -Uri "$SasUri&comp=block&blockid=$([uri]::EscapeDataString($blockId))" -Headers @{ 'x-ms-blob-type' = 'BlockBlob' } -Body $chunk -ContentType 'application/octet-stream' | Out-Null
            $blockIds += $blockId
        }
    }
    Finally {
        $stream.Dispose()
    }
    $blockList = '<?xml version="1.0" encoding="utf-8"?><BlockList>' + (($blockIds | ForEach-Object { "<Latest>$_</Latest>" }) -join '') + '</BlockList>'
    Invoke-WebRequest -Method Put -Uri "$SasUri&comp=blocklist" -Body $blockList -ContentType 'application/xml' | Out-Null
}

Function Publish-IntuneWinContent([String]$AppId, $Package) {
    $base = "$graphBase/$AppId/microsoft.graph.win32LobApp"
    $contentVersion = Invoke-Graph POST "$base/contentVersions" @{}
    $file = Invoke-Graph POST "$base/contentVersions/$($contentVersion.id)/files" @{
        '@odata.type' = '#microsoft.graph.mobileAppContentFile'
        name          = $Package.FileName
        size          = $Package.UnencryptedSize
        sizeEncrypted = $Package.EncryptedSize
        manifest      = $null
        isDependency  = $false
    }
    $fileUri = "$base/contentVersions/$($contentVersion.id)/files/$($file.id)"
    $file = Wait-ContentFile $fileUri 'azureStorageUriRequest'
    Send-AzureBlob $file.azureStorageUri $Package.EncryptedFile
    Invoke-Graph POST "$fileUri/commit" @{ fileEncryptionInfo = $Package.EncryptionInfo } | Out-Null
    Wait-ContentFile $fileUri 'commitFile' | Out-Null
    Return $contentVersion.id
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
    $knownScripts = Get-KnownDetectionScripts
    $found = Get-WingetFWApps
    Write-Status "$($found.Count) WingetFW apps found"
    $rows = ForEach ($listed in $found) {
        $app = Invoke-Graph GET "$graphBase/$($listed.id)?`$expand=assignments"
        $notesVersion = Get-NotesVersion $app.notes
        $install = Convert-WingetFWCommandLine -CommandLine $app.installCommandLine -Map $map -KnownVersion $notesVersion
        $uninstall = Convert-WingetFWCommandLine -CommandLine $app.uninstallCommandLine -Map $map -KnownVersion $notesVersion
        $detection = Get-DetectionInfo $app $knownScripts
        $warnings = @($install.Warnings) + @($uninstall.Warnings | ForEach-Object { "Uninstall: $_" })
        If ($detection.AppId -and $install.Package -and $detection.AppId -ine $install.Package) { $warnings += "Detection script checks '$($detection.AppId)' but the install command uses '$($install.Package)'" }
        $errors = @($install.Errors) + @($uninstall.Errors | ForEach-Object { "Uninstall: $_" })
        $upToDate = $notesVersion -eq $target -and $install.New -eq $install.Original -and $uninstall.New -eq $uninstall.Original
        [PSCustomObject]@{
            Update                  = If ($errors -or $upToDate) { 'No' } Else { 'Yes' }
            AppId                   = $app.id
            DisplayName             = $app.displayName
            Publisher               = $app.publisher
            Assignments             = @($app.assignments).Count
            CurrentWingetFWVersion  = $install.DetectedVersion
            TargetWingetFWVersion   = $target
            DetectionRule           = $detection.Rule
            DetectionAppId          = $detection.AppId
            InstallCommandOld       = $app.installCommandLine
            InstallCommandNew       = $install.New
            InstallChanges          = $install.Changes -join ' | '
            UninstallCommandOld     = $app.uninstallCommandLine
            UninstallCommandNew     = $uninstall.New
            UninstallChanges        = $uninstall.Changes -join ' | '
            Warnings                = $warnings -join ' | '
            Errors                  = If ($upToDate -and -not $errors) { "Already WingetFW $target" } Else { $errors -join ' | ' }
        }
    }
    $rows = @($rows | Sort-Object DisplayName)
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
    $package = Get-IntuneWinPackage $IntuneWinFile
    Try {
        If ($package.SetupFile -ne 'Deploy-Application.exe') { Throw "Setup file of $IntuneWinFile is '$($package.SetupFile)', expected Deploy-Application.exe" }
        Connect-Intune 'DeviceManagementApps.ReadWrite.All'
        $results = ForEach ($row in $rows) {
            $status = ''
            Try {
                $app = Invoke-Graph GET "$graphBase/$($row.AppId)"
                If ($app.installCommandLine -ne $row.InstallCommandOld -or [String]$app.uninstallCommandLine -ne $row.UninstallCommandOld) {
                    $status = 'Skipped: command lines were changed in Intune after the export'
                }
                Else {
                    # The CSV values may have been edited, so they are validated again
                    $install = Convert-WingetFWCommandLine -CommandLine $row.InstallCommandNew -Map $map -KnownVersion $target
                    $uninstall = Convert-WingetFWCommandLine -CommandLine $row.UninstallCommandNew -Map $map -KnownVersion $target
                    $errors = @($install.Errors) + @($uninstall.Errors | ForEach-Object { "Uninstall: $_" })
                    If ($errors) {
                        $status = "Skipped: $($errors -join ' | ')"
                    }
                    ElseIf ($PSCmdlet.ShouldProcess("$($app.displayName) ($($app.id))", "Upload WingetFW $target and set the new command lines")) {
                        Write-Status "Updating $($app.displayName)"
                        $contentVersion = Publish-IntuneWinContent $app.id $package
                        Invoke-Graph PATCH "$graphBase/$($app.id)" @{
                            '@odata.type'           = '#microsoft.graph.win32LobApp'
                            committedContentVersion = $contentVersion
                            fileName                = [IO.Path]::GetFileName($IntuneWinFile)
                            setupFilePath           = $package.SetupFile
                            installCommandLine      = $install.New
                            uninstallCommandLine    = If ($row.UninstallCommandOld) { $uninstall.New } Else { $app.uninstallCommandLine }
                            notes                   = Set-NotesVersion $app.notes $target
                        } | Out-Null
                        $status = "Updated to WingetFW $target (content version $contentVersion)"
                    }
                    Else {
                        $status = 'WhatIf: would be updated'
                    }
                }
            }
            Catch {
                $status = "Failed: $($_.Exception.Message)"
            }
            Write-Status "$($row.DisplayName): $status"
            $row | Select-Object *, @{ n = 'Result'; e = { $status } }
        }
        $resultPath = Join-Path ([IO.Path]::GetDirectoryName((Resolve-Path -LiteralPath $CsvPath).Path)) ("{0}-result.csv" -f [IO.Path]::GetFileNameWithoutExtension($CsvPath))
        $results | Export-Csv -LiteralPath $resultPath -NoTypeInformation -Encoding UTF8
        Write-Status "Result written: $resultPath"
    }
    Finally {
        Remove-Item -LiteralPath $package.EncryptedFile -Force -ErrorAction SilentlyContinue
    }
}
