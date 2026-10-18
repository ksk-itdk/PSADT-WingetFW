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

    Needs PowerShell 7.4 or later. Search needs Microsoft.WinGet.Client, manifest details need powershell-yaml.

.NOTES
    Maintained by: KSKITDK
    Version      : 0.1.0

    Release notes
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
