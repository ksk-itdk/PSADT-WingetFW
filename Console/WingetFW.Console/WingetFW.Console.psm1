<#
.SYNOPSIS
    WingetFW.Console - logic of the WingetFW Console: search, manifest details, command lines, detection scripts.

.DESCRIPTION
    Search   : Find-WingetFWPackage searches a winget source with Microsoft.WinGet.Client.
    Details  : Get-WingetFWManifest reads the manifest of a package version from GitHub winget-pkgs
               (source winget) with powershell-yaml. Other sources (msstore, REST) return the text of winget show.
    Build    : New-WingetFWCommandLine builds the Invoke-AppDeployToolkit.exe command line and checks it with
               the same option rules as WingetFW (exit code 60001 / 69001). ConvertFrom-WingetFWCommandLine
               reads a command line back into parameters.
               Parameter names and accepted values come from Invoke-AppDeployToolkit.ps1 of the newest
               Toolkit\WinGetFW<version> folder, the option rules from Tools\WingetFW-ParameterMap.psd1.
    Detection: New-WingetFWDetectionScript fills in the newest template from Toolkit\Detection.
    Intune   : Connect-WingetFWIntune (delegated sign-in), New-WingetFWIntuneWin (IntuneWinAppUtil.exe),
               Find-WingetFWGroup, New-WingetFWIntuneApp (create, upload, assign). Get-WingetFWIntuneWinPackage,
               Publish-WingetFWIntuneWinContent and Invoke-WingetFWGraph are also used by Tools\Update-WingetFWIntuneApps.ps1.
    Inventory: Get-WingetFWIntuneInventory lists the WingetFW apps in Intune with their command lines converted to the
               current version (Convert-WingetFWCommandLine), detection script and mod file; Update-WingetFWIntuneApp
               updates one app (-WhatIf = dry run). Tools\Update-WingetFWIntuneApps.ps1 -Export and -Apply use the same functions.

    Needs PowerShell 7.4 or later. Search needs Microsoft.WinGet.Client, manifest details need powershell-yaml,
    Intune needs Microsoft.Graph.Authentication.

.NOTES
    Maintained by: KSKITDK
    Version      : 0.3.0

    Release notes
    0.3.0  - Inventory and upgrade (phase CON-3): Get-WingetFWIntuneInventory, Update-WingetFWIntuneApp,
             Get-WingetFWModFileInfo. The conversion and app list functions of Tools\Update-WingetFWIntuneApps.ps1
             moved here (Convert-WingetFWCommandLine, Get-WingetFWIntuneAppList, Get-WingetFWDetectionInfo,
             Get-WingetFWNotesVersion, Set-WingetFWNotesVersion).
    0.2.0  - Intune publish (phase CON-2): sign-in, .intunewin with IntuneWinAppUtil.exe (Microsoft signature checked),
             group search, Win32 app with detection script, return codes (69002 = retry), requirements and assignments.
           - The Graph and upload functions of Tools\Update-WingetFWIntuneApps.ps1 moved here.
    0.1.0  - First version (phase CON-1): search, manifest details, command line builder, detection scripts.

.LINK
    https://github.com/ksk-itdk/PSADT-WingetFW
#>

Set-StrictMode -Version 1
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

$Script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
$Script:ManifestBaseUri = 'https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests'
$Script:PackageInfo = $null
$Script:ParameterMap = $null

#region Private functions

function Get-WingetFWParameterMap
{
    if (-not $Script:ParameterMap)
    {
        $Script:ParameterMap = Import-PowerShellDataFile -LiteralPath (Join-Path -Path $Script:RepoRoot -ChildPath 'Tools\WingetFW-ParameterMap.psd1')
    }
    $Script:ParameterMap
}

function Import-WingetFWRequiredModule
{
    param ([string]$Name, [string]$Purpose)

    if (Get-Module -Name $Name) { return }
    if (-not (Get-Module -Name $Name -ListAvailable))
    {
        throw "$Purpose needs the PowerShell module $Name. Install it with: Install-PSResource -Name $Name -Scope CurrentUser"
    }
    Import-Module -Name $Name -ErrorAction Stop
}

function Format-WingetFWArgument
{
    param ([string]$Name, [object]$Value, [string]$Type)

    if ($Type -eq 'Switch') { return "-$Name" }
    "-$Name '$(([string]$Value) -replace "'", "''")'"
}

# Merges the root fields of an installer manifest into each installer; installer fields win, switches merge per key
function ConvertFrom-WingetFWManifestData
{
    param ([System.Collections.IDictionary]$VersionData, [System.Collections.IDictionary]$InstallerData, [System.Collections.IDictionary]$LocaleData)

    $skip = @('Installers', 'PackageIdentifier', 'PackageVersion', 'ManifestType', 'ManifestVersion')
    $installers = foreach ($installer in @($InstallerData['Installers']))
    {
        $merged = @{}
        foreach ($key in $InstallerData.Keys) { if ($key -notin $skip) { $merged[$key] = $InstallerData[$key] } }
        foreach ($key in $installer.Keys) { $merged[$key] = $installer[$key] }
        $switches = @{}
        foreach ($source in @($InstallerData['InstallerSwitches'], $installer['InstallerSwitches']))
        {
            if ($source -is [System.Collections.IDictionary]) { foreach ($key in $source.Keys) { $switches[$key] = $source[$key] } }
        }
        $entry = @($merged['AppsAndFeaturesEntries'] | Where-Object { $_ }) | Select-Object -First 1
        $productCode = if ($merged['ProductCode']) { $merged['ProductCode'] } elseif ($entry) { $entry['ProductCode'] }
        $releaseDate = $merged['ReleaseDate']
        if ($releaseDate -is [datetime]) { $releaseDate = $releaseDate.ToString('yyyy-MM-dd') }

        [pscustomobject]@{
            Architecture         = [string]$merged['Architecture']
            InstallerType        = [string]$merged['InstallerType']
            NestedInstallerType  = [string]$merged['NestedInstallerType']
            Scope                = [string]$merged['Scope']
            Locale               = [string]$merged['InstallerLocale']
            Silent               = [string]$switches['Silent']
            SilentWithProgress   = [string]$switches['SilentWithProgress']
            Custom               = [string]$switches['Custom']
            ProductCode          = [string]$productCode
            DisplayName          = if ($entry) { [string]$entry['DisplayName'] } else { '' }
            DisplayVersion       = if ($entry) { [string]$entry['DisplayVersion'] } else { '' }
            UpgradeCode          = if ($entry) { [string]$entry['UpgradeCode'] } else { '' }
            ElevationRequirement = [string]$merged['ElevationRequirement']
            UpgradeBehavior      = [string]$merged['UpgradeBehavior']
            MinimumOSVersion     = [string]$merged['MinimumOSVersion']
            ReleaseDate          = [string]$releaseDate
            InstallerUrl         = [string]$merged['InstallerUrl']
        }
    }

    $dependencies = foreach ($installer in @($InstallerData) + @($InstallerData['Installers']))
    {
        $dep = $installer['Dependencies']
        if ($dep -isnot [System.Collections.IDictionary]) { continue }
        foreach ($package in @($dep['PackageDependencies'] | Where-Object { $_ }))
        {
            if ($package['MinimumVersion']) { "$($package['PackageIdentifier']) (>= $($package['MinimumVersion']))" } else { [string]$package['PackageIdentifier'] }
        }
        foreach ($kind in 'WindowsFeatures', 'WindowsLibraries', 'ExternalDependencies')
        {
            foreach ($item in @($dep[$kind] | Where-Object { $_ })) { "$item ($kind)" }
        }
    }

    [pscustomobject]@{
        Id               = [string]$VersionData['PackageIdentifier']
        Version          = [string]$VersionData['PackageVersion']
        Name             = [string]$LocaleData['PackageName']
        Publisher        = [string]$LocaleData['Publisher']
        Moniker          = [string]$LocaleData['Moniker']
        ShortDescription = [string]$LocaleData['ShortDescription']
        License          = [string]$LocaleData['License']
        PackageUrl       = [string]$LocaleData['PackageUrl']
        PublisherUrl     = [string]$LocaleData['PublisherUrl']
        Tags             = @($LocaleData['Tags'] | Where-Object { $_ } | ForEach-Object { [string]$_ })
        Dependencies     = @($dependencies | Select-Object -Unique)
        Installers       = @($installers)
        ShowText         = $null
    }
}

#endregion

#region Public functions

function Get-WingetFWPackageInfo
{
    <#
    .SYNOPSIS
        Reads the parameters (name, type, accepted values) and the version of a WingetFW package.
    .PARAMETER Path
        Package folder. Default: the newest Toolkit\WinGetFW<version> folder.
    #>
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [string]$Path
    )

    if (-not $Path -and $Script:PackageInfo) { return $Script:PackageInfo }
    $cache = $false
    if (-not $Path)
    {
        $Path = Get-ChildItem -LiteralPath (Join-Path -Path $Script:RepoRoot -ChildPath 'Toolkit') -Directory |
            Where-Object { $_.Name -match '^WinGetFW(\d+\.\d+\.\d+)$' } |
            Sort-Object -Property { [version]($_.Name -replace '^WinGetFW', '') } |
            Select-Object -Last 1 -ExpandProperty FullName
        if (-not $Path) { throw "No Toolkit\WinGetFW<version> folder found in $Script:RepoRoot" }
        $cache = $true
    }
    $scriptFile = Join-Path -Path $Path -ChildPath 'Invoke-AppDeployToolkit.ps1'
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptFile, [ref]$null, [ref]$parseErrors)
    if ($parseErrors) { throw "$scriptFile could not be parsed: $($parseErrors[0].Message)" }

    $parameters = [ordered]@{}
    foreach ($parameter in $ast.ParamBlock.Parameters)
    {
        $validateSet = $parameter.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' } | Select-Object -First 1
        $parameters[$parameter.Name.VariablePath.UserPath] = [pscustomobject]@{
            Type   = if ($parameter.StaticType -eq [System.Management.Automation.SwitchParameter]) { 'Switch' } else { 'String' }
            Values = @(if ($validateSet) { $validateSet.PositionalArguments | ForEach-Object { $_.Value } })
        }
    }
    $info = [pscustomobject]@{
        Path       = $Path
        Version    = [regex]::Match($ast.Extent.Text, "(?m)^\s*AppVersion\s*=\s*'([^']*)'").Groups[1].Value
        Parameters = $parameters
    }
    if ($cache) { $Script:PackageInfo = $info }
    $info
}

function Find-WingetFWPackage
{
    <#
    .SYNOPSIS
        Searches a winget source by name, ID, moniker or tag (Microsoft.WinGet.Client).
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [Parameter()]
        [string]$Source
    )

    Import-WingetFWRequiredModule -Name 'Microsoft.WinGet.Client' -Purpose 'Search'
    $findParams = @{ Query = $Query }
    if ($Source) { $findParams.Source = $Source }
    foreach ($package in @(Find-WinGetPackage @findParams))
    {
        [pscustomobject]@{
            Name              = $package.Name
            Id                = $package.Id
            Version           = $package.Version
            Source            = $package.Source
            AvailableVersions = @($package.AvailableVersions)
        }
    }
}

function Get-WingetFWManifest
{
    <#
    .SYNOPSIS
        Returns the manifest details of one package version: installers, scopes, switches, product codes.
    .DESCRIPTION
        Source winget: the manifest files are read from GitHub winget-pkgs. Other sources: winget show,
        returned as text in ShowText (Installers is empty).
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter()]
        [string]$Source = 'winget'
    )

    if ($Source -ne 'winget')
    {
        $wingetArgs = @('show', '--id', $Id, '--exact', '--source', $Source, '--accept-source-agreements', '--disable-interactivity')
        if ($Version -and $Version -ne 'Unknown') { $wingetArgs += @('--version', $Version) }
        $oldEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        try { $lines = & winget.exe @wingetArgs 2>&1 }
        finally { [Console]::OutputEncoding = $oldEncoding }
        # Drop the progress spinner lines
        $text = (@($lines | ForEach-Object { "$_" } | Where-Object { $_ -notmatch '^\s*[-\\|/]?\s*$' -or $_ -eq '' }) -join "`n").Trim()
        return [pscustomobject]@{
            Id = $Id; Version = $Version; Name = ''; Publisher = ''; Moniker = ''; ShortDescription = ''; License = ''
            PackageUrl = ''; PublisherUrl = ''; Tags = @(); Dependencies = @(); Installers = @(); ShowText = $text
        }
    }

    Import-WingetFWRequiredModule -Name 'powershell-yaml' -Purpose 'Manifest details'
    $folder = '{0}/{1}/{2}/{3}' -f $Script:ManifestBaseUri, $Id.Substring(0, 1).ToLowerInvariant(), ($Id -replace '\.', '/'), $Version
    $read = {
        param ($FileName)
        try { (Invoke-WebRequest -Uri "$folder/$FileName" -UseBasicParsing).Content | ConvertFrom-Yaml }
        catch { throw "Could not read $folder/${FileName}: $($_.Exception.Message)" }
    }

    $versionData = & $read "$Id.yaml"
    if ($versionData['ManifestType'] -eq 'singleton')
    {
        $installerData = $versionData
        $localeData = $versionData
    }
    else
    {
        $installerData = & $read "$Id.installer.yaml"
        $localeData = & $read "$Id.locale.$($versionData['DefaultLocale']).yaml"
    }
    $manifest = ConvertFrom-WingetFWManifestData -VersionData $versionData -InstallerData $installerData -LocaleData $localeData
    # The folder name is the version as winget shows it (YAML can turn 1.10 into the number 1.1)
    $manifest.Version = $Version
    $manifest
}

function ConvertFrom-WingetFWCommandLine
{
    <#
    .SYNOPSIS
        Reads an Invoke-AppDeployToolkit.exe command line (or only its arguments) into parameters.
    .OUTPUTS
        Exe (text before and including the exe, empty when only arguments were given), Parameters (ordered), Errors.
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$CommandLine
    )

    $known = (Get-WingetFWPackageInfo).Parameters
    $result = [pscustomobject]@{ Exe = ''; Parameters = [ordered]@{}; Errors = [System.Collections.Generic.List[string]]::new() }
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $result }

    $argText = $CommandLine
    $match = [regex]::Match($CommandLine, '(?i)^\s*(.*?"?[^"\s]*(Deploy-Application|Invoke-AppDeployToolkit)(\.exe)?"?)(\s|$)')
    if ($match.Success)
    {
        $result.Exe = $match.Groups[1].Value.Trim()
        $argText = $CommandLine.Substring($match.Groups[1].Index + $match.Groups[1].Length)
    }

    # The exe passes the arguments to powershell.exe -Command, so the PowerShell parser reads them the same way
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput("x $argText", [ref]$null, [ref]$parseErrors)
    if ($parseErrors)
    {
        $result.Errors.Add("The command line could not be read: $($parseErrors[0].Message)")
        return $result
    }
    $command = $ast.Find({ param ($a) $a -is [System.Management.Automation.Language.CommandAst] }, $true)
    $elements = @($command.CommandElements | Select-Object -Skip 1)
    $valueOf = {
        param ($Element, $Name)
        if ($Element -is [System.Management.Automation.Language.ScriptBlockExpressionAst])
        {
            $result.Errors.Add("-$Name value $($Element.Extent.Text) is not quoted; Invoke-AppDeployToolkit.exe drops the braces. Use single quotes.")
        }
        if ($Element.PSObject.Properties['StringConstantType'] -and $Element.StringConstantType -eq 'DoubleQuoted' -and $Element.Value -match '\s')
        {
            $result.Errors.Add("-$Name value is in double quotes and has spaces; Invoke-AppDeployToolkit.exe then fails with exit code 1. Use single quotes.")
        }
        switch ($Element.GetType().Name)
        {
            'StringConstantExpressionAst' { return $Element.Value }
            'ExpandableStringExpressionAst' { return $Element.Value }
            'ConstantExpressionAst' { return [string]$Element.Value }
            default { return $Element.Extent.Text }
        }
    }

    for ($i = 0; $i -lt $elements.Count; $i++)
    {
        $element = $elements[$i]
        if ($element -isnot [System.Management.Automation.Language.CommandParameterAst])
        {
            $result.Errors.Add("Value without a parameter name: $($element.Extent.Text)")
            continue
        }
        $name = $known.Keys | Where-Object { $_ -ieq $element.ParameterName } | Select-Object -First 1
        $type = if ($name) { $known[$name].Type } else { 'String' }
        if (-not $name)
        {
            $result.Errors.Add("Unknown parameter -$($element.ParameterName)")
            $name = $element.ParameterName
        }
        if ($result.Parameters.Contains($name)) { $result.Errors.Add("-$name is used more than once") }

        if ($type -eq 'Switch')
        {
            $result.Parameters[$name] = if ($element.Argument) { $element.Argument.Extent.Text -notmatch '^\$false$' } else { $true }
            continue
        }
        if ($element.Argument) { $result.Parameters[$name] = & $valueOf $element.Argument $name; continue }
        if ($i + 1 -lt $elements.Count -and $elements[$i + 1] -isnot [System.Management.Automation.Language.CommandParameterAst])
        {
            $i++
            $result.Parameters[$name] = & $valueOf $elements[$i] $name
            continue
        }
        $result.Errors.Add("-$name has no value")
    }
    $result
}

function New-WingetFWCommandLine
{
    <#
    .SYNOPSIS
        Builds an Invoke-AppDeployToolkit.exe command line and checks it with the WingetFW option rules.
    .DESCRIPTION
        Values are written in single quotes (Invoke-AppDeployToolkit.exe fails on double-quoted values with spaces).
        Switches with $false and empty values are left out. Accepted values get the casing of the package.
        Errors are the cases where WingetFW stops with 60001 or 69001 (or PSAppDeployToolkit does not start).
    .PARAMETER Parameters
        Parameter name = value. Switches: $true. DeploymentType defaults to Install.
    .PARAMETER Uninstall
        Build the uninstall command for the same app: DeploymentType Uninstall, without Action, ForceRepair,
        version (an upgraded app would not be found) and the options winget uninstall does not support.
        The left-out parameters are listed in Dropped.
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Parameters,

        [Parameter()]
        [switch]$Uninstall
    )

    $map = Get-WingetFWParameterMap
    $known = (Get-WingetFWPackageInfo).Parameters
    $result = [pscustomobject]@{
        CommandLine = ''
        Parameters  = [ordered]@{}
        Action      = ''
        Errors      = [System.Collections.Generic.List[string]]::new()
        Warnings    = [System.Collections.Generic.List[string]]::new()
        Dropped     = [System.Collections.Generic.List[string]]::new()
    }

    $values = [ordered]@{ DeploymentType = 'Install' }
    foreach ($key in $Parameters.Keys)
    {
        $name = $known.Keys | Where-Object { $_ -ieq $key } | Select-Object -First 1
        if (-not $name)
        {
            $result.Errors.Add("Unknown parameter -$key")
            continue
        }
        $value = $Parameters[$key]
        if ($known[$name].Type -eq 'Switch')
        {
            if ($value -is [System.Management.Automation.SwitchParameter]) { $value = $value.IsPresent }
            if (-not [bool]$value) { continue }
            $value = $true
        }
        else
        {
            if ([string]::IsNullOrWhiteSpace([string]$value)) { continue }
            $value = ([string]$value).Trim()
            $accepted = $known[$name].Values
            if ($accepted)
            {
                $exact = $accepted | Where-Object { $_ -ieq $value } | Select-Object -First 1
                if ($exact) { $value = $exact }
                else { $result.Errors.Add("-$name '$value' is not one of: $($accepted -join ', ')") }
            }
            if ($value -match '"')
            {
                $result.Warnings.Add("-$name contains double quotes. Invoke-AppDeployToolkit.exe passes the command line to PowerShell inside double quotes, so they do not reach WingetFW as typed. Use single quotes inside the value.")
            }
        }
        $values[$name] = $value
    }

    if ($Uninstall)
    {
        $values['DeploymentType'] = 'Uninstall'
        foreach ($name in @('Action', 'ForceRepair', 'version'))
        {
            if ($values.Contains($name)) { $values.Remove($name); $result.Dropped.Add("-$name") }
        }
    }

    $deploymentType = $values['DeploymentType']
    $action = if ($values.Contains('Action')) { $values['Action'] } else { $deploymentType }
    if ($values.Contains('ForceRepair'))
    {
        if ($deploymentType -eq 'Repair') { $action = 'install' }
        else { $result.Warnings.Add('-ForceRepair is ignored unless -DeploymentType is Repair') }
    }
    $action = $action.ToLowerInvariant()
    $result.Action = $action
    $allowed = @($map.ActionOptions[$action])

    foreach ($name in @($values.Keys))
    {
        if ($name -in $map.FrameworkParameters -or $name -in $allowed) { continue }
        if ($Uninstall)
        {
            $values.Remove($name)
            $result.Dropped.Add("-$name")
            continue
        }
        $result.Errors.Add("-$name is not an option with winget $action. Allowed: -$($allowed -join ', -')")
    }

    $used = @($values.Keys)
    foreach ($group in $map.ConflictGroups)
    {
        $conflict = @($group | Where-Object { $_ -in $used })
        if ($conflict.Count -gt 1) { $result.Errors.Add("-$($conflict -join ' and -') cannot be used together. Use only one of -$($group -join ', -').") }
    }
    foreach ($key in $map.Requires.Keys)
    {
        if ($key -in $used -and $map.Requires[$key] -notin $used) { $result.Errors.Add("-$key requires -$($map.Requires[$key])") }
    }
    if (-not @($map.PackageParameters | Where-Object { $_ -in $used }).Count)
    {
        $result.Errors.Add('No package specified. Use -id, -name, -moniker, -wingetmanifest, -productcode or -importfile (WingetFW exit code 69001)')
    }
    if ($values['Mode'] -eq 'User' -and $values['scope'] -eq 'Machine')
    {
        $result.Warnings.Add('-Mode User runs winget as the user without admin rights; -scope Machine needs admin rights')
    }

    # DeploymentType and Action first, then the order they were given in
    $ordered = [ordered]@{ DeploymentType = $deploymentType }
    if ($values.Contains('Action')) { $ordered['Action'] = $values['Action'] }
    foreach ($name in $values.Keys) { if (-not $ordered.Contains($name)) { $ordered[$name] = $values[$name] } }
    $result.Parameters = $ordered
    $arguments = foreach ($name in $ordered.Keys) { Format-WingetFWArgument -Name $name -Value $ordered[$name] -Type $known[$name].Type }
    $result.CommandLine = "$($map.ExeName) $($arguments -join ' ')"
    $result
}

function New-WingetFWDetectionScript
{
    <#
    .SYNOPSIS
        Creates an Intune detection script from the newest template in Toolkit\Detection.
    .PARAMETER Type
        Winget: wingetv<version>.ps1 (winget list --id). Registry: registryversionregexv.<version>.ps1 (uninstall keys, HKLM only).
    .PARAMETER Id
        winget package ID (Type Winget).
    .PARAMETER AppName
        DisplayName in the uninstall keys, wildcards allowed (Type Registry).
    .PARAMETER AppVersion
        Minimum DisplayVersion (Type Registry). 0 = any version.
    .PARAMETER Path
        Save the script to this file (same encoding as the template).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Winget', 'Registry')]
        [string]$Type,

        [Parameter()]
        [string]$Id,

        [Parameter()]
        [string]$AppName,

        [Parameter()]
        [string]$AppVersion = '0',

        [Parameter()]
        [string]$Path
    )

    $pattern = if ($Type -eq 'Winget') { '^wingetv(\d+\.\d+\.\d+)\.ps1$' } else { '^registryversionregexv\.(\d+\.\d+\.\d+)\.ps1$' }
    $template = Get-ChildItem -LiteralPath (Join-Path -Path $Script:RepoRoot -ChildPath 'Toolkit\Detection') -File |
        Where-Object { $_.Name -match $pattern } |
        Sort-Object -Property { [version]([regex]::Match($_.Name, $pattern).Groups[1].Value) } |
        Select-Object -Last 1
    if (-not $template) { throw "No $Type detection template found in Toolkit\Detection" }

    if ($Type -eq 'Winget')
    {
        if ([string]::IsNullOrWhiteSpace($Id) -or $Id -match '\s') { throw 'Id is required and cannot contain spaces' }
        $values = [ordered]@{ app = $Id }
    }
    else
    {
        if ([string]::IsNullOrWhiteSpace($AppName)) { throw 'AppName is required' }
        $values = [ordered]@{ AppName = $AppName; AppVersion = $(if ($AppVersion) { $AppVersion } else { '0' }) }
    }

    $bytes = [System.IO.File]::ReadAllBytes($template.FullName)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false).GetString($bytes, $(if ($hasBom) { 3 } else { 0 }), $bytes.Length - $(if ($hasBom) { 3 } else { 0 }))
    foreach ($name in $values.Keys)
    {
        # Only the unindented assignment; the indented line in .EXAMPLE stays as it is
        $regex = [regex]"(?m)^\`$$name = `"[^`"]*`""
        if ($regex.Matches($text).Count -ne 1) { throw "$($template.Name) does not have exactly one line `$$name = `"...`"" }
        $escaped = $values[$name] -replace '([`$"])', '`$1'
        $text = $regex.Replace($text, { param ($m) "`$$name = `"$escaped`"" }, 1)
    }

    if ($Path -and $PSCmdlet.ShouldProcess($Path, 'Save detection script'))
    {
        [System.IO.File]::WriteAllText($Path, $text, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $hasBom))
    }
    [pscustomobject]@{
        Template = $template.Name
        Text     = $text
    }
}

#endregion

#region Intune (Microsoft Graph beta)

$Script:GraphBase = 'https://graph.microsoft.com/beta'
$Script:IntuneWinAppUtilUri = 'https://raw.githubusercontent.com/microsoft/Microsoft-Win32-Content-Prep-Tool/master/IntuneWinAppUtil.exe'
$Script:IntuneScopes = @('DeviceManagementApps.ReadWrite.All', 'Group.Read.All')

# Return codes of every WingetFW app: the Intune defaults, and 69002 (skipped by a mod file) is retried
$Script:IntuneReturnCodes = @(
    @{ returnCode = 0; type = 'success' }
    @{ returnCode = 1707; type = 'success' }
    @{ returnCode = 3010; type = 'softReboot' }
    @{ returnCode = 1641; type = 'hardReboot' }
    @{ returnCode = 1618; type = 'retry' }
    @{ returnCode = 69002; type = 'retry' }
)

function Wait-WingetFWContentFile
{
    param ([string]$Uri, [string]$Stage)

    for ($i = 0; $i -lt 60; $i++)
    {
        $file = Invoke-WingetFWGraph GET $Uri
        if ($file.uploadState -eq "${Stage}Success") { return $file }
        if ($file.uploadState -match "^${Stage}(Failed|TimedOut)$") { throw "Content file state $($file.uploadState)" }
        Start-Sleep -Seconds 5
    }
    throw "Content file did not reach ${Stage}Success within 5 minutes (state $($file.uploadState))"
}

function Send-WingetFWAzureBlob
{
    param ([string]$SasUri, [string]$Path)

    $chunkSize = 6MB
    $blockIds = [System.Collections.Generic.List[string]]::new()
    $stream = [System.IO.File]::OpenRead($Path)
    try
    {
        $buffer = [byte[]]::new($chunkSize)
        while (($read = $stream.Read($buffer, 0, $chunkSize)) -gt 0)
        {
            $chunk = [byte[]]::new($read)
            [Array]::Copy($buffer, $chunk, $read)
            $blockId = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($blockIds.Count.ToString('0000')))
            $null = Invoke-WebRequest -Method Put -Uri "$SasUri&comp=block&blockid=$([uri]::EscapeDataString($blockId))" -Headers @{ 'x-ms-blob-type' = 'BlockBlob' } -Body $chunk -ContentType 'application/octet-stream'
            $blockIds.Add($blockId)
        }
    }
    finally { $stream.Dispose() }
    $blockList = '<?xml version="1.0" encoding="utf-8"?><BlockList>' + (($blockIds | ForEach-Object { "<Latest>$_</Latest>" }) -join '') + '</BlockList>'
    $null = Invoke-WebRequest -Method Put -Uri "$SasUri&comp=blocklist" -Body $blockList -ContentType 'application/xml'
}

function New-WingetFWIntuneAppBody
{
    param
    (
        [string]$DisplayName, [string]$Publisher, [string]$Description, [string]$InformationUrl, [string]$Notes,
        [string]$FileName, [string]$SetupFile, [string]$InstallCommandLine, [string]$UninstallCommandLine,
        [string]$RunAsAccount, [string]$DetectionScript, [string]$AllowedArchitectures, [string]$MinimumWindowsRelease
    )

    # Intune runs detection scripts in Windows PowerShell 5.1, which needs the BOM to read UTF-8
    $scriptBytes = [System.Text.Encoding]::UTF8.GetPreamble() + [System.Text.Encoding]::UTF8.GetBytes($DetectionScript)
    [ordered]@{
        '@odata.type'                  = '#microsoft.graph.win32LobApp'
        displayName                    = $DisplayName
        description                    = $(if ($Description) { $Description } else { $DisplayName })
        publisher                      = $Publisher
        informationUrl                 = $(if ($InformationUrl) { $InformationUrl } else { $null })
        notes                          = $Notes
        isFeatured                     = $false
        fileName                       = $FileName
        setupFilePath                  = $SetupFile
        installCommandLine             = $InstallCommandLine
        uninstallCommandLine           = $UninstallCommandLine
        installExperience              = [ordered]@{
            '@odata.type'         = '#microsoft.graph.win32LobAppInstallExperience'
            runAsAccount          = $RunAsAccount
            deviceRestartBehavior = 'basedOnReturnCode'
            maxRunTimeInMinutes   = 60
        }
        returnCodes                    = @($Script:IntuneReturnCodes | ForEach-Object { [ordered]@{ '@odata.type' = '#microsoft.graph.win32LobAppReturnCode'; returnCode = $_.returnCode; type = $_.type } })
        rules                          = @(
            [ordered]@{
                '@odata.type'         = '#microsoft.graph.win32LobAppPowerShellScriptRule'
                ruleType              = 'detection'
                enforceSignatureCheck = $false
                runAs32Bit            = $false
                scriptContent         = [Convert]::ToBase64String($scriptBytes)
                operationType         = 'notConfigured'
                operator              = 'notConfigured'
                comparisonValue       = $null
            }
        )
        allowedArchitectures           = $AllowedArchitectures
        applicableArchitectures        = 'none'
        minimumSupportedWindowsRelease = $MinimumWindowsRelease
    }
}

function New-WingetFWAssignmentBody
{
    param ([object[]]$Assignments)

    @{
        mobileAppAssignments = @(foreach ($assignment in $Assignments)
            {
                [ordered]@{
                    '@odata.type' = '#microsoft.graph.mobileAppAssignment'
                    intent        = $assignment.Intent
                    target        = [ordered]@{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $assignment.GroupId }
                    settings      = [ordered]@{
                        '@odata.type'                = '#microsoft.graph.win32LobAppAssignmentSettings'
                        notifications                = 'showAll'
                        deliveryOptimizationPriority = 'notConfigured'
                        restartSettings              = $null
                        installTimeSettings          = $null
                    }
                }
            })
    }
}

function Invoke-WingetFWGraph
{
    <#
    .SYNOPSIS
        Calls Microsoft Graph with the current Connect-MgGraph session; the body is sent as JSON.
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Method,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Uri,

        [Parameter(Position = 2)]
        [object]$Body
    )

    $request = @{ Method = $Method; Uri = $Uri; OutputType = 'PSObject' }
    if ($null -ne $Body)
    {
        $request.Body = $Body | ConvertTo-Json -Depth 10
        $request.ContentType = 'application/json'
    }
    Invoke-MgGraphRequest @request
}

function Connect-WingetFWIntune
{
    <#
    .SYNOPSIS
        Signs in to Microsoft Graph as the admin (delegated) with the permissions the Console needs.
    #>
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [string]$TenantId
    )

    Import-WingetFWRequiredModule -Name 'Microsoft.Graph.Authentication' -Purpose 'Publishing to Intune'
    $connect = @{ Scopes = $Script:IntuneScopes; NoWelcome = $true }
    if ($TenantId) { $connect.TenantId = $TenantId }
    Connect-MgGraph @connect
    $context = Get-MgContext
    $missing = @($Script:IntuneScopes | Where-Object { $_ -notin $context.Scopes })
    if ($missing)
    {
        throw "The sign-in does not have $($missing -join ', '). Run Disconnect-MgGraph, sign in again and consent to the permissions."
    }
    $context
}

function Get-WingetFWIntuneWinPackage
{
    <#
    .SYNOPSIS
        Reads a .intunewin file: setup file, sizes, encryption info. The encrypted content is extracted to a temp file (EncryptedFile).
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path
    )

    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try
    {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq 'IntuneWinPackage/Metadata/Detection.xml' }
        if (-not $entry) { throw "$Path is not a .intunewin file (Detection.xml missing)" }
        $reader = [System.IO.StreamReader]::new($entry.Open())
        [xml]$detection = $reader.ReadToEnd()
        $reader.Close()
        $info = $detection.ApplicationInfo
        $content = $zip.Entries | Where-Object { $_.FullName -eq "IntuneWinPackage/Contents/$($info.FileName)" }
        $encryptedFile = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('WingetFW-{0}.bin' -f [guid]::NewGuid().ToString('N'))
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($content, $encryptedFile, $true)
        [pscustomobject]@{
            FileName        = $info.FileName
            SetupFile       = $info.SetupFile
            UnencryptedSize = [int64]$info.UnencryptedContentSize
            EncryptedFile   = $encryptedFile
            EncryptedSize   = (Get-Item -LiteralPath $encryptedFile).Length
            EncryptionInfo  = @{
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
    finally { $zip.Dispose() }
}

function Publish-WingetFWIntuneWinContent
{
    <#
    .SYNOPSIS
        Uploads a .intunewin (from Get-WingetFWIntuneWinPackage) as a new content version of a Win32 app and returns the content version ID.
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$AppId,

        [Parameter(Mandatory = $true, Position = 1)]
        [object]$Package
    )

    $base = "$Script:GraphBase/deviceAppManagement/mobileApps/$AppId/microsoft.graph.win32LobApp"
    $contentVersion = Invoke-WingetFWGraph POST "$base/contentVersions" @{}
    $file = Invoke-WingetFWGraph POST "$base/contentVersions/$($contentVersion.id)/files" @{
        '@odata.type' = '#microsoft.graph.mobileAppContentFile'
        name          = $Package.FileName
        size          = $Package.UnencryptedSize
        sizeEncrypted = $Package.EncryptedSize
        manifest      = $null
        isDependency  = $false
    }
    $fileUri = "$base/contentVersions/$($contentVersion.id)/files/$($file.id)"
    $file = Wait-WingetFWContentFile $fileUri 'azureStorageUriRequest'
    Send-WingetFWAzureBlob $file.azureStorageUri $Package.EncryptedFile
    $null = Invoke-WingetFWGraph POST "$fileUri/commit" @{ fileEncryptionInfo = $Package.EncryptionInfo }
    $null = Wait-WingetFWContentFile $fileUri 'commitFile'
    $contentVersion.id
}

function New-WingetFWIntuneWin
{
    <#
    .SYNOPSIS
        Creates the .intunewin of a WingetFW package with IntuneWinAppUtil.exe and returns its path.
    .DESCRIPTION
        IntuneWinAppUtil.exe is downloaded from github.com/microsoft/Microsoft-Win32-Content-Prep-Tool to
        LOCALAPPDATA\WingetFW\Console when it is not there yet. It only runs with a valid Microsoft signature.
    .PARAMETER PackagePath
        WingetFW package folder. Default: the newest Toolkit\WinGetFW<version>.
    .PARAMETER OutputFolder
        Default: LOCALAPPDATA\WingetFW\Console\IntuneWin\<package folder name>.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter()]
        [string]$PackagePath = (Get-WingetFWPackageInfo).Path,

        [Parameter()]
        [string]$OutputFolder
    )

    $toolFolder = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'WingetFW\Console'
    if (-not $OutputFolder) { $OutputFolder = Join-Path -Path $toolFolder -ChildPath "IntuneWin\$(Split-Path -Path $PackagePath -Leaf)" }
    $tool = Join-Path -Path $toolFolder -ChildPath 'IntuneWinAppUtil.exe'
    $setupFile = (Get-WingetFWParameterMap).ExeName
    $output = Join-Path -Path $OutputFolder -ChildPath ([System.IO.Path]::ChangeExtension($setupFile, '.intunewin'))
    if (-not $PSCmdlet.ShouldProcess($output, "Create from $PackagePath")) { return }

    if (-not (Test-Path -LiteralPath $tool))
    {
        $null = New-Item -Path $toolFolder -ItemType Directory -Force
        Invoke-WebRequest -Uri $Script:IntuneWinAppUtilUri -OutFile $tool -UseBasicParsing
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $tool
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '\bO=Microsoft Corporation\b')
    {
        Remove-Item -LiteralPath $tool -Force
        throw "IntuneWinAppUtil.exe is not signed by Microsoft (status $($signature.Status)); it was deleted."
    }

    $null = New-Item -Path $OutputFolder -ItemType Directory -Force
    if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Force }
    $text = & $tool -c $PackagePath -s $setupFile -o $OutputFolder -q 2>&1 | Out-String
    if (-not (Test-Path -LiteralPath $output)) { throw "IntuneWinAppUtil.exe did not create $output (exit code $LASTEXITCODE): $($text.Trim())" }
    $output
}

function Find-WingetFWGroup
{
    <#
    .SYNOPSIS
        Finds Entra ID groups whose display name starts with the given text (at most 25).
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $filter = "startswith(displayName,'$($Name -replace "'", "''")')"
    $uri = "$Script:GraphBase/groups?`$filter=$([uri]::EscapeDataString($filter))&`$select=id,displayName,description&`$top=25"
    foreach ($group in @((Invoke-WingetFWGraph GET $uri).value))
    {
        [pscustomobject]@{ Id = $group.id; DisplayName = $group.displayName; Description = $group.description }
    }
}

function New-WingetFWIntuneApp
{
    <#
    .SYNOPSIS
        Creates a WingetFW Win32 app in Intune: app, .intunewin upload, detection script, return codes, requirements, assignments.
    .DESCRIPTION
        Needs a Connect-WingetFWIntune session. Return codes: Intune defaults plus 69002 (skipped by a mod file) as retry.
        When the upload fails, the app is left in Intune without content; the error has its ID.
    .PARAMETER RunAsAccount
        system (WingetFW -Mode Admin) or user (-Mode User).
    .PARAMETER AllowedArchitectures
        Intune requirement, for example x64 or x64,arm64.
    .PARAMETER MinimumWindowsRelease
        Intune requirement, for example 1809, Windows10_22H2 or Windows11_23H2.
    .PARAMETER Assignments
        Objects with GroupId and Intent (required, available, uninstall).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,

        [Parameter(Mandatory = $true)]
        [string]$Publisher,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string]$InformationUrl,

        [Parameter(Mandatory = $true)]
        [string]$InstallCommandLine,

        [Parameter(Mandatory = $true)]
        [string]$UninstallCommandLine,

        [Parameter()]
        [ValidateSet('system', 'user')]
        [string]$RunAsAccount = 'system',

        [Parameter(Mandatory = $true)]
        [string]$DetectionScript,

        [Parameter(Mandatory = $true)]
        [string]$IntuneWinFile,

        [Parameter()]
        [string]$AllowedArchitectures = 'x64',

        [Parameter()]
        [string]$MinimumWindowsRelease = '1809',

        [Parameter()]
        [string]$WingetFWVersion = (Get-WingetFWPackageInfo).Version,

        [Parameter()]
        [object[]]$Assignments = @()
    )

    foreach ($assignment in $Assignments)
    {
        if ($assignment.Intent -notin 'required', 'available', 'uninstall') { throw "Assignment intent '$($assignment.Intent)' must be required, available or uninstall" }
        if ($assignment.GroupId -notmatch '^[0-9a-fA-F-]{36}$') { throw "Assignment group ID '$($assignment.GroupId)' is not a GUID" }
    }
    $package = Get-WingetFWIntuneWinPackage $IntuneWinFile
    try
    {
        $exeName = (Get-WingetFWParameterMap).ExeName
        if ($package.SetupFile -ne $exeName) { throw "The setup file of $IntuneWinFile is '$($package.SetupFile)', expected $exeName" }
        $body = New-WingetFWIntuneAppBody -DisplayName $DisplayName -Publisher $Publisher -Description $Description -InformationUrl $InformationUrl `
            -Notes "WingetFW $WingetFWVersion" -FileName ([System.IO.Path]::GetFileName($IntuneWinFile)) -SetupFile $package.SetupFile `
            -InstallCommandLine $InstallCommandLine -UninstallCommandLine $UninstallCommandLine -RunAsAccount $RunAsAccount `
            -DetectionScript $DetectionScript -AllowedArchitectures $AllowedArchitectures -MinimumWindowsRelease $MinimumWindowsRelease
        if (-not $PSCmdlet.ShouldProcess($DisplayName, 'Create Win32 app in Intune')) { return }

        $appsUri = "$Script:GraphBase/deviceAppManagement/mobileApps"
        $app = Invoke-WingetFWGraph POST $appsUri $body
        try
        {
            $contentVersion = Publish-WingetFWIntuneWinContent $app.id $package
            $null = Invoke-WingetFWGraph PATCH "$appsUri/$($app.id)" @{ '@odata.type' = '#microsoft.graph.win32LobApp'; committedContentVersion = $contentVersion }
            if ($Assignments.Count)
            {
                # An app can only be assigned when it is published
                for ($i = 0; $i -lt 24 -and (Invoke-WingetFWGraph GET "$appsUri/$($app.id)").publishingState -ne 'published'; $i++) { Start-Sleep -Seconds 5 }
                $null = Invoke-WingetFWGraph POST "$appsUri/$($app.id)/assign" (New-WingetFWAssignmentBody -Assignments $Assignments)
            }
        }
        catch
        {
            throw "The app '$DisplayName' was created in Intune (ID $($app.id)), but the upload or assignment failed: $($_.Exception.Message)"
        }
        [pscustomobject]@{
            Id             = $app.id
            DisplayName    = $DisplayName
            ContentVersion = $contentVersion
            Assignments    = $Assignments.Count
        }
    }
    finally { Remove-Item -LiteralPath $package.EncryptedFile -Force -ErrorAction SilentlyContinue }
}

#endregion

#region Inventory and upgrade (also used by Tools\Update-WingetFWIntuneApps.ps1)

$Script:IntuneAppsUri = "$Script:GraphBase/deviceAppManagement/mobileApps"
$Script:KnownDetectionScripts = @{}

function Get-WingetFWMapName
{
    # The key with its original casing, $null if not found
    param ([System.Collections.IDictionary]$Table, [string]$Name)
    foreach ($key in $Table.Keys) { if ($key -ieq $Name) { return $key } }
    $null
}

function Get-WingetFWAstValue
{
    param ($Ast)
    switch ($Ast.GetType().Name)
    {
        'StringConstantExpressionAst' { return $Ast.Value }
        'ExpandableStringExpressionAst' { return $Ast.Value }
        'ConstantExpressionAst' { return [string]$Ast.Value }
        # Unquoted {GUID}
        default { return $Ast.Extent.Text }
    }
}

function Format-WingetFWConvertedArgument
{
    param ($Item)
    if ($Item.IsSwitch)
    {
        if ($Item.SwitchArgument) { return "-$($Item.Name):$($Item.SwitchArgument)" }
        return "-$($Item.Name)"
    }
    "-$($Item.Name) '$(([string]$Item.Value) -replace "'", "''")'"
}

function ConvertFrom-WingetFWText
{
    # Splits raw winget arguments (3.x -WingetCM / -WingetScope) into WingetFW parameters
    param ([string]$Text, [System.Collections.IDictionary]$Map, $Result)

    $tokens = @([regex]::Matches($Text, '"[^"]*"|''[^'']*''|\S+') | ForEach-Object { $_.Value })
    $items = @()
    $i = 0
    while ($i -lt $tokens.Count)
    {
        $token = $tokens[$i]
        $key = Get-WingetFWMapName $Map.WingetOptions $token
        if (-not $key)
        {
            $Result.Errors.Add("Unknown winget argument '$token' in '$Text'")
            $i++
            # Skip the value of the unknown option
            while ($i -lt $tokens.Count -and -not (Get-WingetFWMapName $Map.WingetOptions $tokens[$i]) -and $tokens[$i] -notmatch '^-') { $i++ }
            continue
        }
        $option = $Map.WingetOptions[$key]
        $value = $null
        if ($option.Value)
        {
            # Values with spaces were often not quoted in 3.x, so take everything up to the next winget option
            $parts = @()
            $i++
            while ($i -lt $tokens.Count -and -not (Get-WingetFWMapName $Map.WingetOptions $tokens[$i]))
            {
                $parts += $tokens[$i].Trim('"').Trim("'")
                $i++
            }
            if ($parts.Count -eq 0)
            {
                $Result.Errors.Add("winget argument '$token' has no value in '$Text'")
                continue
            }
            $value = $parts -join ' '
        }
        else
        {
            $i++
        }
        if (-not $option.Parameter)
        {
            $Result.Changes.Add("'$token' dropped (WingetFW adds it itself)")
            continue
        }
        if ($option.Parameter -eq 'scope') { $value = (Get-Culture).TextInfo.ToTitleCase($value.ToLower()) }
        $items += [pscustomobject]@{ Name = $option.Parameter; Value = $value; IsSwitch = -not $option.Value; SwitchArgument = $null; FromOld = $true }
    }
    $items
}

function Convert-WingetFWCommandLine
{
    <#
    .SYNOPSIS
        Converts a WingetFW command line of any version (3.x, 4.x, 5.x) to the current version and checks it.
    .OUTPUTS
        Original, New, DetectedVersion, Package, Parameters (of the new command), Changes, Warnings, Errors.
    .PARAMETER KnownVersion
        WingetFW version from the app notes, if known.
    #>
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [string]$CommandLine,

        [Parameter()]
        [System.Collections.IDictionary]$Map = (Get-WingetFWParameterMap),

        [Parameter()]
        [string]$KnownVersion
    )

    $result = [pscustomobject]@{
        Original        = $CommandLine
        New             = $CommandLine
        DetectedVersion = ''
        Package         = ''
        Parameters      = [ordered]@{}
        Changes         = [System.Collections.Generic.List[string]]::new()
        Warnings        = [System.Collections.Generic.List[string]]::new()
        Errors          = [System.Collections.Generic.List[string]]::new()
    }
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $result }

    $match = [regex]::Match($CommandLine, '(?i)"?(Deploy-Application|Invoke-AppDeployToolkit)(\.exe)?"?')
    if (-not $match.Success)
    {
        $result.Errors.Add('Deploy-Application.exe or Invoke-AppDeployToolkit.exe not found in the command line')
        return $result
    }
    # Text before the exe (for example ServiceUI.exe -process:explorer.exe) is kept as it is
    $prefix = $CommandLine.Substring(0, $match.Index)
    $exe = $match.Value
    $argText = $CommandLine.Substring($match.Index + $match.Length)
    $isOldExe = $match.Groups[1].Value -ieq 'Deploy-Application'
    if ($isOldExe)
    {
        $exe = $Map.ExeName
        $result.Changes.Add("$($match.Value.Trim('"')) replaced by $($Map.ExeName) (WingetFW 5.0.0, PSAppDeployToolkit 4)")
    }
    if ($prefix -match '(?i)ServiceUI')
    {
        $result.Errors.Add('ServiceUI.exe is not in the WingetFW 5.0.0 package; remove it from the command line or add it to the package')
    }

    # Both exes pass the arguments to powershell.exe -Command, so the PowerShell parser reads them the same way
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput("x $argText", [ref]$null, [ref]$parseErrors)
    if ($parseErrors)
    {
        $result.Errors.Add("Command line could not be parsed: $($parseErrors[0].Message)")
        return $result
    }
    $command = $ast.Find({ param ($a) $a -is [System.Management.Automation.Language.CommandAst] }, $true)
    $elements = @($command.CommandElements | Select-Object -Skip 1)

    $items = @()
    for ($i = 0; $i -lt $elements.Count; $i++)
    {
        $element = $elements[$i]
        if ($element -isnot [System.Management.Automation.Language.CommandParameterAst])
        {
            $result.Errors.Add("Value without parameter name: $($element.Extent.Text)")
            continue
        }
        $name = Get-WingetFWMapName $Map.Parameters $element.ParameterName
        $type = if ($name) { $Map.Parameters[$name] } else { $name = Get-WingetFWMapName $Map.OldParameters $element.ParameterName; if ($name) { $Map.OldParameters[$name] } }
        if (-not $name)
        {
            $result.Errors.Add("Unknown parameter -$($element.ParameterName)")
            $name = $element.ParameterName
            $type = 'String'
        }
        $item = [pscustomobject]@{ Name = $name; Value = $null; IsSwitch = ($type -eq 'Switch'); SwitchArgument = $null; FromOld = $false }
        if ($element.Argument)
        {
            if ($item.IsSwitch) { $item.SwitchArgument = $element.Argument.Extent.Text } else { $item.Value = Get-WingetFWAstValue $element.Argument }
        }
        elseif (-not $item.IsSwitch)
        {
            if ($i + 1 -lt $elements.Count -and $elements[$i + 1] -isnot [System.Management.Automation.Language.CommandParameterAst])
            {
                $i++
                $item.Value = Get-WingetFWAstValue $elements[$i]
            }
            else
            {
                $result.Errors.Add("Parameter -$name has no value")
            }
        }
        $items += $item
    }

    $names = @($items | ForEach-Object { $_.Name })
    $isV3 = [bool]($names | Where-Object { $_ -in $Map.V3Parameters })
    $isOld4 = [bool]($names | Where-Object { $_ -in @('testverbose', 'wait') }) -or [bool]($items | Where-Object { $_.Name -eq 'scope' -and $_.Value -in $Map.RemovedScopeValues })
    $isNew4 = [bool]($names | Where-Object { $_ -in $Map.V407Parameters })
    $result.DetectedVersion = if ($KnownVersion) { $KnownVersion } elseif (-not $isOldExe) { '5.0.0 or later' } elseif ($isV3) { '3.x' } elseif ($isOld4) { '4.0.0 - 4.0.6' } elseif ($isNew4) { '4.0.7 - 4.0.8' } else { '4.x' }

    # Convert old parameters
    $converted = @()
    foreach ($item in $items)
    {
        if ($Map.RenamedParameters.ContainsKey($item.Name))
        {
            $newName = $Map.RenamedParameters[$item.Name]
            $result.Changes.Add("-$($item.Name) renamed to -$newName")
            $item.Name = $newName
            $item.FromOld = $true
            $converted += $item
        }
        elseif ($Map.RemovedParameters.ContainsKey($item.Name))
        {
            $result.Changes.Add("-$($item.Name) removed: $($Map.RemovedParameters[$item.Name])")
        }
        elseif ($item.Name -in $Map.WingetTextParameters)
        {
            $newItems = @(ConvertFrom-WingetFWText -Text $item.Value -Map $Map -Result $result)
            $result.Changes.Add("-$($item.Name) '$($item.Value)' converted to: $(($newItems | ForEach-Object { Format-WingetFWConvertedArgument $_ }) -join ' ')")
            $converted += $newItems
        }
        elseif ($item.Name -eq 'scope' -and $item.Value -in $Map.RemovedScopeValues)
        {
            $result.Changes.Add("-scope '$($item.Value)' removed (no longer supported; it was not passed to winget)")
        }
        else
        {
            $converted += $item
        }
    }

    # The same parameter twice (for example -WingetScope and --scope in -WingetCM): keep the first
    $unique = @()
    foreach ($item in $converted)
    {
        if ($unique | Where-Object { $_.Name -eq $item.Name })
        {
            $result.Warnings.Add("-$($item.Name) was set more than once; the first value is kept")
            continue
        }
        $unique += $item
    }
    $converted = $unique

    $get = { param ($n) $converted | Where-Object { $_.Name -eq $n -and (-not $_.IsSwitch -or $_.SwitchArgument -notmatch '\$false') } | Select-Object -First 1 }
    $deploymentType = if (& $get 'DeploymentType') { (& $get 'DeploymentType').Value } else { 'Install' }

    # 3.x always ran winget with --silent
    $deploymentAction = if (& $get 'Action') { (& $get 'Action').Value } else { $deploymentType }
    $overrideKept = (& $get 'override') -and $Map.ActionOptions[$deploymentAction.ToLower()] -contains 'override'
    if ($isV3 -and -not (& $get 'silent'))
    {
        if ($overrideKept) { $result.Changes.Add('-silent not added: 3.x sent --silent, but -override cannot be combined with -silent') }
        elseif (& $get 'interactive') { $result.Changes.Add('-silent not added because -interactive is used') }
        else
        {
            $converted += [pscustomobject]@{ Name = 'silent'; Value = $null; IsSwitch = $true; SwitchArgument = $null; FromOld = $true }
            $result.Changes.Add('-silent added (3.x always ran winget with --silent)')
        }
    }

    # Before 4.0.7 Repair always uninstalled and installed again
    $knownNew = $false
    if ($KnownVersion) { try { $knownNew = [version]$KnownVersion -ge [version]'4.0.7' } catch { $knownNew = $false } }
    if ($deploymentType -ieq 'Repair' -and -not $isNew4 -and -not $knownNew -and -not (& $get $Map.OldRepairParameter))
    {
        $converted += [pscustomobject]@{ Name = $Map.OldRepairParameter; Value = $null; IsSwitch = $true; SwitchArgument = $null; FromOld = $true }
        $result.Changes.Add("-$($Map.OldRepairParameter) added (Repair before 4.0.7 always uninstalled and installed again)")
    }

    # Validate against the rules of the new version
    $forceRepair = [bool](& $get 'ForceRepair')
    $action = if (& $get 'Action') { (& $get 'Action').Value } else { $deploymentType }
    if ($forceRepair)
    {
        if ($deploymentType -ieq 'Repair') { $action = 'install' } else { $result.Warnings.Add('-ForceRepair is ignored unless -DeploymentType is Repair') }
    }
    $action = $action.ToLower()
    $allowed = $Map.ActionOptions[$action]
    if (-not $allowed)
    {
        $result.Errors.Add("Unknown action '$action'")
        $allowed = @()
    }
    $used = @($converted | Where-Object { $_.Name -notin $Map.FrameworkParameters -and $_.Name -in $Map.Parameters.Keys -and (-not $_.IsSwitch -or $_.SwitchArgument -notmatch '\$false') })
    $kept = @()
    foreach ($item in $converted)
    {
        if ($item -in $used -and $item.Name -notin $allowed)
        {
            if ($item.FromOld)
            {
                # Older versions passed it to winget anyway, where it had no effect or failed
                $result.Changes.Add("-$($item.Name) removed: winget $action does not support it")
                continue
            }
            $result.Errors.Add("-$($item.Name) is not supported with winget $action")
        }
        $kept += $item
    }
    $converted = $kept
    $usedNames = @($converted | Where-Object { $_ -in $used } | ForEach-Object { $_.Name })
    foreach ($group in $Map.ConflictGroups)
    {
        $conflict = @($usedNames | Where-Object { $_ -in $group })
        if ($conflict.Count -gt 1) { $result.Errors.Add("-$($conflict -join ' and -') cannot be used together") }
    }
    foreach ($key in $Map.Requires.Keys)
    {
        if ($key -in $usedNames -and $Map.Requires[$key] -notin $usedNames) { $result.Errors.Add("-$key requires -$($Map.Requires[$key])") }
    }
    $package = @($converted | Where-Object { $_.Name -in $Map.PackageParameters -and $_.Value } | Select-Object -First 1)
    if ($package) { $result.Package = $package[0].Value } else { $result.Errors.Add('No package parameter (id, name, moniker, wingetmanifest, productcode or importfile)') }
    if ($isOldExe -and 'AllowRebootPassThru' -notin $names)
    {
        $result.Changes.Add('Reboot exit codes (3010, 1641) are now passed to Intune; add -SuppressRebootPassThru to keep the old behaviour')
    }

    foreach ($item in $converted) { $result.Parameters[$item.Name] = if ($item.IsSwitch) { $item.SwitchArgument -notmatch '\$false' } else { $item.Value } }
    $result.New = ("$prefix$exe " + (($converted | ForEach-Object { Format-WingetFWConvertedArgument $_ }) -join ' ')).TrimEnd()
    if ($result.New -ne $CommandLine -and $result.Changes.Count -eq 0) { $result.Changes.Add('Values written in single quotes (the exe fails on double-quoted values with spaces)') }
    $result
}

function Get-WingetFWNotesVersion
{
    <#
    .SYNOPSIS
        The WingetFW version in the app notes ("WingetFW x.y.z"), empty when there is none.
    #>
    [CmdletBinding()]
    param ([Parameter(Position = 0)][string]$Notes)
    [regex]::Match([string]$Notes, 'WingetFW (\d+\.\d+\.\d+)').Groups[1].Value
}

function Set-WingetFWNotesVersion
{
    <#
    .SYNOPSIS
        Returns the app notes with "WingetFW <Version>" replaced or added. Changes nothing in Intune.
    #>
    [CmdletBinding()]
    param ([Parameter(Position = 0)][string]$Notes, [Parameter(Position = 1)][string]$Version)
    if ($Notes -match 'WingetFW \d+\.\d+\.\d+') { return [regex]::Replace($Notes, 'WingetFW \d+\.\d+\.\d+', "WingetFW $Version") }
    if ([string]::IsNullOrWhiteSpace($Notes)) { return "WingetFW $Version" }
    "$Notes`nWingetFW $Version"
}

function Get-WingetFWNormalizedScriptHash
{
    # App-specific lines ($app = "...", $AppName/$AppVersion) are ignored, so the same script version matches for every app
    param ([string]$Text)
    $lines = $Text -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^\$(app|AppName|AppVersion)\s*=' }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes))
}

function Get-WingetFWDetectionInfo
{
    <#
    .SYNOPSIS
        Detection rule of an Intune Win32 app: which Toolkit\Detection script it uses and the package ID in it.
    .OUTPUTS
        Rule (for example "Script wingetv2.0.2", "Script (custom)", "Registry", "None") and AppId.
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [object]$App,

        [Parameter()]
        [string]$DetectionScriptPath = (Join-Path -Path $Script:RepoRoot -ChildPath 'Toolkit\Detection')
    )

    if (-not $Script:KnownDetectionScripts.ContainsKey($DetectionScriptPath))
    {
        $known = @{}
        if (Test-Path -LiteralPath $DetectionScriptPath)
        {
            Get-ChildItem -LiteralPath $DetectionScriptPath -Filter '*.ps1' | ForEach-Object { $known[(Get-WingetFWNormalizedScriptHash (Get-Content -LiteralPath $_.FullName -Raw))] = $_.BaseName }
        }
        $Script:KnownDetectionScripts[$DetectionScriptPath] = $known
    }
    $knownScripts = $Script:KnownDetectionScripts[$DetectionScriptPath]

    $rules = @($App.rules | Where-Object { $_.ruleType -eq 'detection' }) + @($App.detectionRules)
    $rules = @($rules | Where-Object { $_ })
    if (-not $rules) { return [pscustomobject]@{ Rule = 'None'; AppId = '' } }
    $script = $rules | Where-Object { $_.'@odata.type' -match 'PowerShellScript' } | Select-Object -First 1
    if (-not $script) { return [pscustomobject]@{ Rule = (($rules | ForEach-Object { $_.'@odata.type' -replace '#microsoft.graph.win32LobApp', '' -replace 'Rule$|Detection$', '' }) -join ', '); AppId = '' } }
    $text = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($script.scriptContent)).TrimStart([char]0xFEFF)
    $name = $knownScripts[(Get-WingetFWNormalizedScriptHash $text)]
    # The parser skips the help block, which has an example $app line
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$parseErrors)
    $assignment = $ast.Find({ param ($a) $a -is [System.Management.Automation.Language.AssignmentStatementAst] -and $a.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $a.Left.VariablePath.UserPath -eq 'app' -and $a.Right.Expression -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)
    $appId = if ($assignment) { $assignment.Right.Expression.Value } elseif ($parseErrors) { [regex]::Match($text, '(?m)^\$app\s*=\s*["'']([^"'']+)["'']').Groups[1].Value } else { '' }
    [pscustomobject]@{
        Rule  = if ($name) { "Script $name" } else { 'Script (custom)' }
        AppId = $appId
    }
}

function Get-WingetFWIntuneAppList
{
    <#
    .SYNOPSIS
        Lists the Win32 apps in Intune whose install command runs WingetFW (Deploy-Application.exe or Invoke-AppDeployToolkit.exe with a package parameter).
    #>
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [System.Collections.IDictionary]$Map = (Get-WingetFWParameterMap)
    )

    $uri = "$Script:IntuneAppsUri`?`$filter=isof('microsoft.graph.win32LobApp')"
    $apps = @()
    do
    {
        try
        {
            $page = Invoke-WingetFWGraph GET $uri
        }
        catch
        {
            if ($_.Exception.Message -match 'Forbidden|403')
            {
                $context = Get-MgContext
                $fix = if ($context.Account) { "The account $($context.Account) needs an Intune role that can read apps, for example Intune Administrator or Application Manager (activate it first if it is a PIM role)." } else { "The app registration $($context.ClientId) needs DeviceManagementApps.Read.All as an application permission with admin consent." }
                throw "Intune refused the request (Forbidden). $fix Details: $($_.Exception.Message)"
            }
            throw
        }
        $apps += @($page.value)
        $uri = $page.'@odata.nextLink'
    } while ($uri)
    Write-Verbose -Message "$($apps.Count) Win32 apps in Intune"
    $pattern = '(?i)(^|\s)-(' + (@($Map.PackageParameters) + @($Map.V3Parameters | Where-Object { $_ -eq 'WingetID' }) -join '|') + ')\b'
    @($apps | Where-Object { $_.installCommandLine -match '(?i)Deploy-Application|Invoke-AppDeployToolkit' -and $_.installCommandLine -match $pattern })
}

function Get-WingetFWModFileInfo
{
    <#
    .SYNOPSIS
        Looks for the app mod file <ScriptRoot>\<Source>\<Id>.ps1 (local folder, UNC share or Azure blob URL with SAS) and checks its signature.
    .OUTPUTS
        Location (SAS signature hidden), Status (Found, NotFound, Unreachable), Signature (Valid, NotSigned, ...) and Signer.
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$ScriptRoot,

        [Parameter()]
        [string]$Source = 'winget',

        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    $result = [pscustomobject]@{ Location = ''; Status = 'NotFound'; Signature = ''; Signer = '' }
    if ($ScriptRoot -match '^https?://')
    {
        $uri = [Uri]$ScriptRoot
        $relative = '{0}/{1}' -f [Uri]::EscapeDataString($Source), [Uri]::EscapeDataString("$Id.ps1")
        $fileUri = '{0}/{1}{2}' -f $uri.GetLeftPart([UriPartial]::Path).TrimEnd('/'), $relative, $uri.Query
        $result.Location = $fileUri -replace '(?i)(sig=)[^&]+', '$1***'
        $file = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('WingetFW-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
        try
        {
            $null = Invoke-WebRequest -Uri $fileUri -OutFile $file -UseBasicParsing
            $result.Status = 'Found'
        }
        catch
        {
            $status = 0
            if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
            $result.Status = if ($status -eq 404) { 'NotFound' } else { 'Unreachable' }
        }
    }
    else
    {
        $file = Join-Path -Path $ScriptRoot -ChildPath "$Source\$Id.ps1"
        $result.Location = $file
        if (-not (Test-Path -LiteralPath $ScriptRoot)) { $result.Status = 'Unreachable' }
        elseif (Test-Path -LiteralPath $file -PathType Leaf) { $result.Status = 'Found' }
    }
    if ($result.Status -eq 'Found')
    {
        $signature = Get-AuthenticodeSignature -LiteralPath $file
        $result.Signature = [string]$signature.Status
        if ($signature.SignerCertificate) { $result.Signer = $signature.SignerCertificate.Subject }
    }
    if ($ScriptRoot -match '^https?://') { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
    $result
}

function Get-WingetFWIntuneInventory
{
    <#
    .SYNOPSIS
        Reads all WingetFW apps in Intune and converts their command lines to the target WingetFW version (nothing is changed).
    .DESCRIPTION
        The rows are the -Export CSV of Tools\Update-WingetFWIntuneApps.ps1. The Console adds Details (package, action,
        assignment intents, mod file); export without it: Select-Object -Property * -ExcludeProperty Details.
    .PARAMETER ScriptRoot
        Optional ScriptRoot of the mod files, to look for each app's mod file.
    #>
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [string]$TargetVersion = (Get-WingetFWPackageInfo).Version,

        [Parameter()]
        [System.Collections.IDictionary]$Map = (Get-WingetFWParameterMap),

        [Parameter()]
        [string]$DetectionScriptPath = (Join-Path -Path $Script:RepoRoot -ChildPath 'Toolkit\Detection'),

        [Parameter()]
        [string]$ScriptRoot
    )

    $rows = foreach ($listed in (Get-WingetFWIntuneAppList -Map $Map))
    {
        $app = Invoke-WingetFWGraph GET "$Script:IntuneAppsUri/$($listed.id)?`$expand=assignments"
        $notesVersion = Get-WingetFWNotesVersion $app.notes
        $install = Convert-WingetFWCommandLine -CommandLine $app.installCommandLine -Map $Map -KnownVersion $notesVersion
        $uninstall = Convert-WingetFWCommandLine -CommandLine $app.uninstallCommandLine -Map $Map -KnownVersion $notesVersion
        $detection = Get-WingetFWDetectionInfo $app -DetectionScriptPath $DetectionScriptPath
        $warnings = @($install.Warnings) + @($uninstall.Warnings | ForEach-Object { "Uninstall: $_" })
        if ($detection.AppId -and $install.Package -and $detection.AppId -ine $install.Package) { $warnings += "Detection script checks '$($detection.AppId)' but the install command uses '$($install.Package)'" }
        $errors = @($install.Errors) + @($uninstall.Errors | ForEach-Object { "Uninstall: $_" })
        $upToDate = $notesVersion -eq $TargetVersion -and $install.New -eq $install.Original -and $uninstall.New -eq $uninstall.Original

        $source = if ($install.Parameters['source']) { [string]$install.Parameters['source'] } else { 'winget' }
        $id = [string]$install.Parameters['id']
        $mod = if ($ScriptRoot -and $id) { Get-WingetFWModFileInfo -ScriptRoot $ScriptRoot -Source $source -Id $id }
        $deploymentType = if ($install.Parameters['DeploymentType']) { $install.Parameters['DeploymentType'] } else { 'Install' }

        [pscustomobject]@{
            Update                 = if ($errors -or $upToDate) { 'No' } else { 'Yes' }
            AppId                  = $app.id
            DisplayName            = $app.displayName
            Publisher              = $app.publisher
            Assignments            = @($app.assignments).Count
            CurrentWingetFWVersion = $install.DetectedVersion
            TargetWingetFWVersion  = $TargetVersion
            DetectionRule          = $detection.Rule
            DetectionAppId         = $detection.AppId
            InstallCommandOld      = $app.installCommandLine
            InstallCommandNew      = $install.New
            InstallChanges         = $install.Changes -join ' | '
            UninstallCommandOld    = $app.uninstallCommandLine
            UninstallCommandNew    = $uninstall.New
            UninstallChanges       = $uninstall.Changes -join ' | '
            Warnings               = $warnings -join ' | '
            Errors                 = if ($upToDate -and -not $errors) { "Already WingetFW $TargetVersion" } else { $errors -join ' | ' }
            Details                = [pscustomobject]@{
                Package     = $install.Package
                Action      = if ($install.Parameters['Action']) { "$deploymentType ($($install.Parameters['Action']))" } else { $deploymentType }
                Mode        = if ($install.Parameters['Mode']) { $install.Parameters['Mode'] } else { 'Admin' }
                Intents     = (@($app.assignments | Group-Object -Property intent | Sort-Object -Property Name | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', ')
                ModSource   = $source
                ModStatus   = if ($mod) { $mod.Status } elseif (-not $ScriptRoot) { '' } else { 'No -id' }
                ModLocation = if ($mod) { $mod.Location } else { '' }
                ModSigned   = if ($mod) { (@($mod.Signature, $mod.Signer) | Where-Object { $_ }) -join ', ' } else { '' }
            }
        }
    }
    @($rows | Sort-Object -Property DisplayName)
}

function Update-WingetFWIntuneApp
{
    <#
    .SYNOPSIS
        Updates one WingetFW app in Intune from an inventory row: new content version, new command lines, notes "WingetFW <version>".
    .DESCRIPTION
        Skipped when the command lines in Intune differ from InstallCommandOld/UninstallCommandOld (changed after the
        inventory) or when the new command lines have errors. With -WhatIf nothing is changed (dry run).
        Returns the result text.
    .PARAMETER Row
        Object with AppId, InstallCommandOld, UninstallCommandOld, InstallCommandNew, UninstallCommandNew
        (a Get-WingetFWIntuneInventory row or a CSV row).
    .PARAMETER Package
        Result of Get-WingetFWIntuneWinPackage. Not needed with -WhatIf.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory = $true)]
        [object]$Row,

        [Parameter()]
        [object]$Package,

        [Parameter()]
        [string]$IntuneWinFile,

        [Parameter()]
        [string]$TargetVersion = (Get-WingetFWPackageInfo).Version,

        [Parameter()]
        [System.Collections.IDictionary]$Map = (Get-WingetFWParameterMap)
    )

    try
    {
        $app = Invoke-WingetFWGraph GET "$Script:IntuneAppsUri/$($Row.AppId)"
        if ($app.installCommandLine -ne $Row.InstallCommandOld -or [string]$app.uninstallCommandLine -ne [string]$Row.UninstallCommandOld)
        {
            return 'Skipped: command lines were changed in Intune after the export'
        }
        # The CSV values may have been edited, so they are validated again
        $install = Convert-WingetFWCommandLine -CommandLine $Row.InstallCommandNew -Map $Map -KnownVersion $TargetVersion
        $uninstall = Convert-WingetFWCommandLine -CommandLine $Row.UninstallCommandNew -Map $Map -KnownVersion $TargetVersion
        $errors = @($install.Errors) + @($uninstall.Errors | ForEach-Object { "Uninstall: $_" })
        if ($errors) { return "Skipped: $($errors -join ' | ')" }
        if (-not $PSCmdlet.ShouldProcess("$($app.displayName) ($($app.id))", "Upload WingetFW $TargetVersion and set the new command lines")) { return 'WhatIf: would be updated' }
        if (-not $Package -or -not $IntuneWinFile) { return 'Failed: no .intunewin package given' }

        $contentVersion = Publish-WingetFWIntuneWinContent $app.id $Package
        $null = Invoke-WingetFWGraph PATCH "$Script:IntuneAppsUri/$($app.id)" @{ '@odata.type' = '#microsoft.graph.win32LobApp'; committedContentVersion = $contentVersion }
        # Intune ignores the other properties when they come in the same PATCH as committedContentVersion
        $null = Invoke-WingetFWGraph PATCH "$Script:IntuneAppsUri/$($app.id)" @{
            '@odata.type'        = '#microsoft.graph.win32LobApp'
            fileName             = [System.IO.Path]::GetFileName($IntuneWinFile)
            setupFilePath        = $Package.SetupFile
            installCommandLine   = $install.New
            uninstallCommandLine = if ($Row.UninstallCommandOld) { $uninstall.New } else { $app.uninstallCommandLine }
            notes                = Set-WingetFWNotesVersion $app.notes $TargetVersion
        }
        "Updated to WingetFW $TargetVersion (content version $contentVersion)"
    }
    catch
    {
        "Failed: $($_.Exception.Message)"
    }
}

#endregion
