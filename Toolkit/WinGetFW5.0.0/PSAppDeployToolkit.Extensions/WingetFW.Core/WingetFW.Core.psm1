<#
.SYNOPSIS
    WingetFW.Core - shared functions for WingetFW, WingetFW Console and WingetFW-Update.

.DESCRIPTION
    Settings : Get-WingetFWSetting reads one setting from the first level that has it:
               1. Policy      HKLM\SOFTWARE\Policies\WingetFW (Intune or GPO)
               2. Command line
               3. Mod file    $Settings of the app's mod file
               4. Local key   HKLM\SOFTWARE\WingetFW
               5. Config file WingetFW.psd1 in the package
               6. Built-in default
    Logging  : Write-WingetFWLog writes to the PSAppDeployToolkit log when a PSADT session is open,
               otherwise to a CMTrace log file (ProgramData\WingetFW\Logs or LOCALAPPDATA\WingetFW\Logs).
    Event log: Register-WingetFWEventLog creates the WingetFW event log; Write-WingetFWEvent writes to it.
    State    : Get-WingetFWState / Set-WingetFWState read and write one JSON file per app.
               Machine: ProgramData\WingetFW\State (SYSTEM and Administrators write, Users read).
               User   : LOCALAPPDATA\WingetFW\State.
    Mods     : Import-WingetFWMod finds, fetches, checks and loads the global and the app mod file;
               Invoke-WingetFWModSection runs one section (PreInstall, Install, PostInstall ...).
               Cache: ProgramData\WingetFW\Cache (SYSTEM and Administrators only) or LOCALAPPDATA\WingetFW\Cache.

    Works in Windows PowerShell 5.1 and PowerShell 7.

.NOTES
    Maintained by: KSKITDK
    Version      : 1.2.0

    Release notes
    1.2.0  - Import-WingetFWMod and Invoke-WingetFWModSection (phase FW-3): ScriptRoot (local, UNC, Azure blob),
             ScriptSyncMode OnDemand/Mirror, UseCachedScriptsWhenOffline, AllowedScriptSources,
             RequireSignedScripts/TrustedSigners, load check (only functions and $Settings at the top level).
    1.1.0  - Get-WingetFWSetting reads ADMX list keys: a subkey with values 1, 2, 3 ... is returned as an
             ordered array, a subkey with named values as an ordered name/value table.
           - Get-WingetFWSetting -AsBoolean converts 1/0, true/false and DWORD values to $true/$false.
    1.0.0  - First version (phase FW-1): settings reader, logging, event log and state files.

.LINK
    https://github.com/ksk-itdk/PSADT-WingetFW
#>

Set-StrictMode -Version 1
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

$Script:SidSystem         = 'S-1-5-18'
$Script:SidAdministrators = 'S-1-5-32-544'
$Script:SidUsers          = 'S-1-5-32-545'

#region Private functions

function Test-WingetFWElevated
{
    $principal = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WingetFWRoot
{
    param ([ValidateSet('Machine', 'User')][string]$Scope)

    if ($Scope -eq 'Machine') { Join-Path -Path $env:ProgramData -ChildPath 'WingetFW' }
    else { Join-Path -Path $env:LOCALAPPDATA -ChildPath 'WingetFW' }
}

function Get-WingetFWRegistryValue
{
    param ([string]$Path, [string]$Name)

    $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    if ($item)
    {
        $value = $item.$Name
        # The comma keeps a REG_MULTI_SZ value as an array, also with one element.
        if ($value -is [array]) { return , $value }
        return $value
    }

    # ADMX list elements write a subkey: values 1, 2, 3 ... (list) or name = value (explicitValue)
    $listPath = Join-Path -Path $Path -ChildPath $Name
    if (-not (Test-Path -LiteralPath $listPath)) { return }
    $key = Get-Item -LiteralPath $listPath
    $names = @($key.GetValueNames() | Where-Object { $_ })
    if (-not $names.Count) { return }
    if (-not @($names | Where-Object { $_ -notmatch '^\d+$' }).Count)
    {
        return , @($names | Sort-Object -Property { [int]$_ } | ForEach-Object { $key.GetValue($_) })
    }
    $map = [ordered]@{}
    foreach ($valueName in $names) { $map[$valueName] = $key.GetValue($valueName) }
    $map
}

function Protect-WingetFWFolder
{
    # SYSTEM and Administrators full control, Users read (not with -NoUsers), owner Administrators, no inherited rules.
    param ([string]$Path, [switch]$NoUsers)

    if (-not (Test-Path -LiteralPath $Path -PathType Container))
    {
        $null = New-Item -Path $Path -ItemType Directory -Force
    }
    $acl = Get-Acl -LiteralPath $Path
    $owner = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
    if ($acl.AreAccessRulesProtected -and $owner -in @($Script:SidAdministrators, $Script:SidSystem)) { return }

    $acl = New-Object -TypeName Security.AccessControl.DirectorySecurity
    $acl.SetOwner((New-Object -TypeName Security.Principal.SecurityIdentifier -ArgumentList $Script:SidAdministrators))
    $acl.SetAccessRuleProtection($true, $false)
    $rules = @(@($Script:SidSystem, 'FullControl'), @($Script:SidAdministrators, 'FullControl'))
    if (-not $NoUsers) { $rules += , @($Script:SidUsers, 'ReadAndExecute') }
    foreach ($rule in $rules)
    {
        $sid = New-Object -TypeName Security.Principal.SecurityIdentifier -ArgumentList $rule[0]
        $acl.AddAccessRule((New-Object -TypeName Security.AccessControl.FileSystemAccessRule -ArgumentList $sid, $rule[1], 'ContainerInherit, ObjectInherit', 'None', 'Allow'))
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}

#endregion

$Script:LogFile = Join-Path -Path (Get-WingetFWRoot -Scope $(if (Test-WingetFWElevated) { 'Machine' } else { 'User' })) -ChildPath 'Logs\WingetFW.log'

#region Logging

function Write-WingetFWLog
{
    <#
    .SYNOPSIS
        Writes a log line to the PSAppDeployToolkit log, or to a CMTrace log file when no PSADT session is open.
    .PARAMETER Message
        Text to log.
    .PARAMETER Severity
        1 = information, 2 = warning, 3 = error.
    .PARAMETER Source
        Component shown in the log.
    .PARAMETER LogFile
        CMTrace log file. When set, the PSADT log is not used.
    .EXAMPLE
        Write-WingetFWLog -Message 'Mod file loaded' -Source 'Mods'
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter()]
        [ValidateRange(1, 3)]
        [int]$Severity = 1,

        [Parameter()]
        [string]$Source = 'WingetFW',

        [Parameter()]
        [string]$LogFile = $Script:LogFile
    )

    Write-Verbose -Message "[$Source] $Message"
    try
    {
        if (-not $PSBoundParameters.ContainsKey('LogFile') -and (Get-Command -Name 'Test-ADTSessionActive' -ErrorAction SilentlyContinue) -and (Test-ADTSessionActive))
        {
            Write-ADTLogEntry -Message $Message -Severity $Severity -Source $Source
            return
        }

        $folder = Split-Path -Path $LogFile -Parent
        if (-not (Test-Path -LiteralPath $folder -PathType Container))
        {
            $null = New-Item -Path $folder -ItemType Directory -Force
        }
        $now = Get-Date
        $culture = [Globalization.CultureInfo]::InvariantCulture
        $offset = '{0:+0;-0;+0}' -f [TimeZoneInfo]::Local.GetUtcOffset($now).TotalMinutes
        $line = '<![LOG[{0}]LOG]!><time="{1}{2}" date="{3}" component="{4}" context="{5}" type="{6}" thread="{7}" file="">' -f $Message, $now.ToString('HH:mm:ss.fff', $culture), $offset, $now.ToString('M-d-yyyy', $culture), $Source, [Security.Principal.WindowsIdentity]::GetCurrent().Name, $Severity, $PID
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    }
    catch
    {
        Write-Warning -Message "Could not write to the WingetFW log: $($_.Exception.Message)"
    }
}

#endregion

#region Settings

function Get-WingetFWSetting
{
    <#
    .SYNOPSIS
        Reads one WingetFW setting from the first level that has a value.
    .DESCRIPTION
        Order: Policy key, command line, mod file, local key, config file, default.
        Returns an object with Name, Value and Source (Policy, CommandLine, Mod, Local, Config, Default or None).
        The value and its source are logged; SAS signatures (sig=...) are masked in the log.
        In the registry a setting is a value, or a subkey with the same name (ADMX list): values 1, 2, 3 ...
        give an ordered array, named values give an ordered name/value table.
    .PARAMETER Name
        Setting name, the same at every level.
    .PARAMETER CommandLine
        Parameters from the command line, for example $PSBoundParameters.
    .PARAMETER ModSettings
        The section of the mod file's $Settings for the current action, for example $Settings.Install.
    .PARAMETER Config
        Settings from the package config file (Import-PowerShellDataFile).
    .PARAMETER Default
        Built-in default. Leave out when there is no default.
    .PARAMETER PolicyPath
        Policy registry key. Default HKLM:\SOFTWARE\Policies\WingetFW.
    .PARAMETER LocalPath
        Local registry key. Default HKLM:\SOFTWARE\WingetFW.
    .PARAMETER AsBoolean
        Return the value as $true or $false: 1, 'true', 'yes', 'on' and $true are $true, everything else $false.
    .EXAMPLE
        Get-WingetFWSetting -Name 'DefaultSilent' -CommandLine $PSBoundParameters -Config $config -Default $true -AsBoolean
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [System.Collections.IDictionary]$CommandLine = @{},

        [Parameter()]
        [System.Collections.IDictionary]$ModSettings = @{},

        [Parameter()]
        [System.Collections.IDictionary]$Config = @{},

        [Parameter()]
        [AllowNull()]
        [object]$Default,

        [Parameter()]
        [string]$PolicyPath = 'HKLM:\SOFTWARE\Policies\WingetFW',

        [Parameter()]
        [string]$LocalPath = 'HKLM:\SOFTWARE\WingetFW',

        [Parameter()]
        [switch]$AsBoolean
    )

    $source = 'None'
    $value = Get-WingetFWRegistryValue -Path $PolicyPath -Name $Name
    if ($null -ne $value) { $source = 'Policy' }
    elseif ($null -ne $CommandLine[$Name]) { $value = $CommandLine[$Name]; $source = 'CommandLine' }
    elseif ($null -ne $ModSettings[$Name]) { $value = $ModSettings[$Name]; $source = 'Mod' }
    else
    {
        $value = Get-WingetFWRegistryValue -Path $LocalPath -Name $Name
        if ($null -ne $value) { $source = 'Local' }
        elseif ($null -ne $Config[$Name]) { $value = $Config[$Name]; $source = 'Config' }
        elseif ($PSBoundParameters.ContainsKey('Default') -and $null -ne $Default) { $value = $Default; $source = 'Default' }
    }

    if ($AsBoolean -and $source -ne 'None')
    {
        $value = if ($value -is [string]) { $value.Trim() -in @('1', 'true', '$true', 'yes', 'on') } else { [bool]$value }
    }

    $text = if ($source -eq 'None') { '<not set>' }
    elseif ($value -is [System.Collections.IDictionary]) { @($value.GetEnumerator() | ForEach-Object { '{0}={1}' -f $_.Key, $_.Value }) -join '; ' }
    else { @($value) -join '; ' }
    $text = ConvertTo-WingetFWLogText $text
    Write-WingetFWLog -Message "Setting [$Name] = [$text] from [$source]" -Source 'Get-WingetFWSetting'
    [pscustomobject]@{ Name = $Name; Value = $value; Source = $source }
}

#endregion

#region Event log

function Register-WingetFWEventLog
{
    <#
    .SYNOPSIS
        Creates the WingetFW event log and event source. Needs administrator rights.
    .PARAMETER LogName
        Event log name. Only the first 8 characters of a custom log name must be unique on the device.
    .PARAMETER Source
        Event source name.
    .EXAMPLE
        Register-WingetFWEventLog
    #>
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [string]$LogName = 'WingetFW',

        [Parameter()]
        [string]$Source = 'WingetFW'
    )

    if (-not (Test-WingetFWElevated)) { throw 'Register-WingetFWEventLog needs administrator rights.' }
    if ([Diagnostics.EventLog]::SourceExists($Source))
    {
        $registeredLog = [Diagnostics.EventLog]::LogNameFromSourceName($Source, '.')
        if ($registeredLog -ne $LogName) { throw "Event source [$Source] is already registered to event log [$registeredLog]." }
        return
    }
    [Diagnostics.EventLog]::CreateEventSource($Source, $LogName)
    Write-WingetFWLog -Message "Created event log [$LogName] with source [$Source]" -Source 'Register-WingetFWEventLog'
}

function Write-WingetFWEvent
{
    <#
    .SYNOPSIS
        Writes an entry to the WingetFW event log.
    .DESCRIPTION
        Creates the event log first when it is missing and the caller is an administrator.
        A failure is written to the WingetFW log as a warning and does not stop the caller.
    .PARAMETER Message
        Event text.
    .PARAMETER EntryType
        Information, Warning or Error.
    .PARAMETER EventId
        Event ID.
    .PARAMETER LogName
        Event log name.
    .PARAMETER Source
        Event source name.
    .EXAMPLE
        Write-WingetFWEvent -Message 'Installed 7zip.7zip 26.04' -EventId 1000
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$EntryType = 'Information',

        [Parameter()]
        [ValidateRange(0, 65535)]
        [int]$EventId = 1000,

        [Parameter()]
        [string]$LogName = 'WingetFW',

        [Parameter()]
        [string]$Source = 'WingetFW'
    )

    try
    {
        if (-not [Diagnostics.EventLog]::Exists($LogName))
        {
            if (-not (Test-WingetFWElevated)) { throw "Event log [$LogName] does not exist. Run Register-WingetFWEventLog as administrator." }
            Register-WingetFWEventLog -LogName $LogName -Source $Source
        }
        $eventLog = New-Object -TypeName Diagnostics.EventLog -ArgumentList $LogName
        try
        {
            $eventLog.Source = $Source
            $eventLog.WriteEntry($Message, [Diagnostics.EventLogEntryType]$EntryType, $EventId)
        }
        finally
        {
            $eventLog.Dispose()
        }
    }
    catch
    {
        Write-WingetFWLog -Message "Could not write to event log [$LogName]: $($_.Exception.Message)" -Severity 2 -Source 'Write-WingetFWEvent'
    }
}

#endregion

#region State

function Get-WingetFWState
{
    <#
    .SYNOPSIS
        Reads the WingetFW state of one app. Returns $null when there is no state file.
    .PARAMETER Id
        Package ID, used as the file name.
    .PARAMETER Scope
        Machine (ProgramData\WingetFW\State) or User (LOCALAPPDATA\WingetFW\State).
    .PARAMETER Root
        Other root folder instead of ProgramData\WingetFW or LOCALAPPDATA\WingetFW (tests, or a user profile read by SYSTEM).
    .EXAMPLE
        Get-WingetFWState -Id '7zip.7zip'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^(?!\.{1,2}$)[^\\/:*?"<>|\x00-\x1f]+$')]
        [string]$Id,

        [Parameter()]
        [ValidateSet('Machine', 'User')]
        [string]$Scope = 'Machine',

        [Parameter()]
        [string]$Root
    )

    if (-not $Root) { $Root = Get-WingetFWRoot -Scope $Scope }
    $file = Join-Path -Path $Root -ChildPath "State\$Id.json"
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $null }
    try
    {
        $state = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
        # PowerShell 7 turns ISO dates into DateTime, 5.1 keeps the string; always return the string.
        if ($state.PSObject.Properties['LastTime'] -and $state.LastTime -is [datetime])
        {
            $state.LastTime = $state.LastTime.ToUniversalTime().ToString('o')
        }
        $state
    }
    catch
    {
        Write-WingetFWLog -Message "State file [$file] could not be read: $($_.Exception.Message)" -Severity 2 -Source 'Get-WingetFWState'
        $null
    }
}

function Set-WingetFWState
{
    <#
    .SYNOPSIS
        Writes the WingetFW state of one app. Only the given values change; the rest is kept.
    .DESCRIPTION
        Call it only when something changed (an action succeeded or failed). The installed version is not
        stored; read it from winget. LastTime (UTC) is set when LastAction or LastResult is given.
        The file is written to a temp file first and then swapped in.
        Machine scope needs administrator rights and secures the folders: SYSTEM and Administrators
        full control, Users read.
    .PARAMETER Id
        Package ID, used as the file name.
    .PARAMETER Scope
        Machine or User.
    .PARAMETER Source
        winget source the app was installed from.
    .PARAMETER ModFile
        Mod file used for the last action.
    .PARAMETER Ring
        Update ring (WingetFW-Update).
    .PARAMETER Pinned
        App is pinned (WingetFW-Update).
    .PARAMETER LastAction
        Install, Uninstall, Repair, Upgrade or Import.
    .PARAMETER LastResult
        Exit code of the last action.
    .PARAMETER Root
        Other root folder instead of ProgramData\WingetFW or LOCALAPPDATA\WingetFW (tests).
    .EXAMPLE
        Set-WingetFWState -Id '7zip.7zip' -Source 'winget' -LastAction 'Install' -LastResult 0
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^(?!\.{1,2}$)[^\\/:*?"<>|\x00-\x1f]+$')]
        [string]$Id,

        [Parameter()]
        [ValidateSet('Machine', 'User')]
        [string]$Scope = 'Machine',

        [Parameter()]
        [string]$Source,

        [Parameter()]
        [string]$ModFile,

        [Parameter()]
        [string]$Ring,

        [Parameter()]
        [bool]$Pinned,

        [Parameter()]
        [ValidateSet('Install', 'Uninstall', 'Repair', 'Upgrade', 'Import')]
        [string]$LastAction,

        [Parameter()]
        [int]$LastResult,

        [Parameter()]
        [string]$Root
    )

    if ($Scope -eq 'Machine' -and -not (Test-WingetFWElevated)) { throw 'Machine state needs administrator rights.' }
    $rootPath = if ($Root) { $Root } else { Get-WingetFWRoot -Scope $Scope }
    $folder = Join-Path -Path $rootPath -ChildPath 'State'
    $file = Join-Path -Path $folder -ChildPath "$Id.json"

    $state = [ordered]@{
        SchemaVersion = 1
        Id            = $Id
        Scope         = $Scope
        UserSid       = $null
        Managed       = $true
        Source        = $null
        ModFile       = $null
        Ring          = $null
        Pinned        = $false
        LastAction    = $null
        LastResult    = $null
        LastTime      = $null
    }
    $existing = Get-WingetFWState -Id $Id -Scope $Scope -Root $rootPath
    if ($existing)
    {
        foreach ($key in @('Source', 'ModFile', 'Ring', 'Pinned', 'LastAction', 'LastResult', 'LastTime'))
        {
            if ($existing.PSObject.Properties[$key]) { $state[$key] = $existing.$key }
        }
    }
    if ($Scope -eq 'User') { $state.UserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
    foreach ($key in @('Source', 'ModFile', 'Ring', 'Pinned', 'LastAction', 'LastResult'))
    {
        if ($PSBoundParameters.ContainsKey($key)) { $state[$key] = $PSBoundParameters[$key] }
    }
    if ($PSBoundParameters.ContainsKey('LastAction') -or $PSBoundParameters.ContainsKey('LastResult'))
    {
        $state.LastTime = (Get-Date).ToUniversalTime().ToString('o')
    }

    if (-not $PSCmdlet.ShouldProcess($file, 'Write WingetFW state')) { return }
    if ($Scope -eq 'Machine')
    {
        Protect-WingetFWFolder -Path $rootPath
        Protect-WingetFWFolder -Path $folder
    }
    elseif (-not (Test-Path -LiteralPath $folder -PathType Container))
    {
        $null = New-Item -Path $folder -ItemType Directory -Force
    }

    $temp = "$file.tmp"
    [IO.File]::WriteAllText($temp, ($state | ConvertTo-Json), (New-Object -TypeName Text.UTF8Encoding -ArgumentList $false))
    if (Test-Path -LiteralPath $file -PathType Leaf) { [IO.File]::Replace($temp, $file, [NullString]::Value) }
    else { [IO.File]::Move($temp, $file) }
    Write-WingetFWLog -Message "State of [$Id] ($Scope) written to [$file]" -Source 'Set-WingetFWState'
}

#endregion

#region Mods

function ConvertTo-WingetFWLogText
{
    param ([string]$Text)
    $Text -replace '(?i)(sig=)[^&;\s]+', '$1***'
}

function Test-WingetFWUrl
{
    param ([string]$Location)
    $Location -match '^https?://'
}

function Get-WingetFWNormalizedLocation
{
    # Lower-case URL without query or full path, ending with a separator, for prefix checks.
    param ([string]$Location)
    if (Test-WingetFWUrl -Location $Location)
    {
        return (([Uri]$Location).GetLeftPart([UriPartial]::Path).TrimEnd('/') + '/').ToLowerInvariant()
    }
    ([IO.Path]::GetFullPath($Location).TrimEnd('\') + '\').ToLowerInvariant()
}

function Test-WingetFWAllowedLocation
{
    param ([string]$Location, [string[]]$Allowed)
    $normalized = Get-WingetFWNormalizedLocation -Location $Location
    foreach ($prefix in @($Allowed | Where-Object { $_ }))
    {
        if ((Test-WingetFWUrl -Location $prefix) -ne (Test-WingetFWUrl -Location $Location)) { continue }
        if ($normalized.StartsWith((Get-WingetFWNormalizedLocation -Location $prefix), [StringComparison]::Ordinal)) { return $true }
    }
    $false
}

function Get-WingetFWCacheName
{
    # One cache folder per ScriptRoot, named by a hash of the root without the SAS query.
    param ([string]$Root)
    $sha = [Security.Cryptography.SHA256]::Create()
    try
    {
        $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes((Get-WingetFWNormalizedLocation -Location $Root)))
    }
    finally
    {
        $sha.Dispose()
    }
    -join ($hash[0..7] | ForEach-Object { $_.ToString('x2') })
}

function Get-WingetFWModUri
{
    param ([string]$Root, [string]$RelativePath)
    $uri = [Uri]$Root
    $path = @($RelativePath -split '[\\/]' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    '{0}/{1}{2}' -f $uri.GetLeftPart([UriPartial]::Path).TrimEnd('/'), $path, $uri.Query
}

function Invoke-WingetFWDownload
{
    # Returns Found (file written to OutFile), NotFound (HTTP 404) or Unreachable.
    param ([string]$Uri, [string]$OutFile)
    $ProgressPreference = 'SilentlyContinue'
    $folder = Split-Path -Path $OutFile -Parent
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { $null = New-Item -Path $folder -ItemType Directory -Force }
    $temp = "$OutFile.download"
    try
    {
        $null = Invoke-WebRequest -Uri $Uri -OutFile $temp -UseBasicParsing -ErrorAction Stop
        Move-Item -LiteralPath $temp -Destination $OutFile -Force
        'Found'
    }
    catch
    {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        $status = 0
        if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        if ($status -eq 404) { return 'NotFound' }
        Write-WingetFWLog -Message "Download of [$(ConvertTo-WingetFWLogText $Uri)] failed: $($_.Exception.Message)" -Severity 2 -Source 'Import-WingetFWMod'
        'Unreachable'
    }
}

function Test-WingetFWRelativePath
{
    param ([string]$RelativePath)
    $RelativePath -and -not [IO.Path]::IsPathRooted($RelativePath) -and -not @($RelativePath -split '[\\/]' | Where-Object { $_ -in @('', '.', '..') -or $_ -match ':' }).Count
}

function Get-WingetFWBlobList
{
    # Blob names below the ScriptRoot URL (Azure Blob "List Blobs", needs read + list); $null when it can't be read.
    param ([string]$Root)
    $uri = [Uri]$Root
    $segments = @($uri.AbsolutePath.Trim('/') -split '/')
    $prefix = @($segments | Select-Object -Skip 1) -join '/'
    if ($prefix) { $prefix += '/' }
    $base = '{0}://{1}/{2}' -f $uri.Scheme, $uri.Authority, $segments[0]
    $query = $uri.Query.TrimStart('?')
    $names = New-Object -TypeName System.Collections.Generic.List[string]
    $marker = ''
    do
    {
        $listUri = '{0}?restype=container&comp=list&prefix={1}' -f $base, [Uri]::EscapeDataString($prefix)
        if ($marker) { $listUri += '&marker=' + [Uri]::EscapeDataString($marker) }
        if ($query) { $listUri += '&' + $query }
        try
        {
            $response = Invoke-WebRequest -Uri $listUri -UseBasicParsing -ErrorAction Stop
        }
        catch
        {
            Write-WingetFWLog -Message "Listing [$(ConvertTo-WingetFWLogText $Root)] failed: $($_.Exception.Message)" -Severity 2 -Source 'Import-WingetFWMod'
            return $null
        }
        $content = $response.Content
        if ($content -is [byte[]]) { $content = [Text.Encoding]::UTF8.GetString($content) }
        [xml]$xml = $content.TrimStart([char]0xFEFF)
        foreach ($blob in @($xml.EnumerationResults.Blobs.Blob))
        {
            if ($blob -and $blob.Name.StartsWith($prefix)) { $names.Add($blob.Name.Substring($prefix.Length)) }
        }
        $marker = [string]$xml.EnumerationResults.NextMarker
    }
    while ($marker)
    , $names.ToArray()
}

function Sync-WingetFWModRoot
{
    # Mirror: copies all .ps1 files of a ScriptRoot to its cache folder and removes the others. $false = can't be reached.
    param ([string]$Root, [string]$CacheDir)
    $copied = New-Object -TypeName System.Collections.Generic.List[string]
    if (Test-WingetFWUrl -Location $Root)
    {
        $names = Get-WingetFWBlobList -Root $Root
        if ($null -eq $names) { return $false }
        foreach ($name in @($names | Where-Object { $_ -like '*.ps1' }))
        {
            $relative = $name -replace '/', '\'
            if (-not (Test-WingetFWRelativePath -RelativePath $relative)) { continue }
            $status = Invoke-WingetFWDownload -Uri (Get-WingetFWModUri -Root $Root -RelativePath $relative) -OutFile (Join-Path -Path $CacheDir -ChildPath $relative)
            if ($status -eq 'Unreachable') { return $false }
            if ($status -eq 'Found') { $copied.Add($relative.ToLowerInvariant()) }
        }
    }
    else
    {
        if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return $false }
        $rootFull = (Get-Item -LiteralPath $Root).FullName.TrimEnd('\')
        foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ps1'))
        {
            $relative = $file.FullName.Substring($rootFull.Length + 1)
            $target = Join-Path -Path $CacheDir -ChildPath $relative
            $targetFolder = Split-Path -Path $target -Parent
            if (-not (Test-Path -LiteralPath $targetFolder -PathType Container)) { $null = New-Item -Path $targetFolder -ItemType Directory -Force }
            Copy-Item -LiteralPath $file.FullName -Destination $target -Force
            $copied.Add($relative.ToLowerInvariant())
        }
    }
    if (Test-Path -LiteralPath $CacheDir -PathType Container)
    {
        $cacheFull = (Get-Item -LiteralPath $CacheDir).FullName.TrimEnd('\')
        foreach ($cached in @(Get-ChildItem -LiteralPath $CacheDir -Recurse -File))
        {
            if (-not $copied.Contains($cached.FullName.Substring($cacheFull.Length + 1).ToLowerInvariant()))
            {
                Remove-Item -LiteralPath $cached.FullName -Force
            }
        }
    }
    Write-WingetFWLog -Message "Mirrored $($copied.Count) mod file(s) from [$(ConvertTo-WingetFWLogText $Root)]" -Source 'Import-WingetFWMod'
    $true
}

function Get-WingetFWModFromRoot
{
    # Returns Status (Found, NotFound, Unreachable), Bytes and Origin of one mod file in one ScriptRoot.
    param ([string]$Root, [string]$RelativePath, [string]$CacheDir, [string]$SyncMode)
    $cacheFile = Join-Path -Path $CacheDir -ChildPath $RelativePath
    $isUrl = Test-WingetFWUrl -Location $Root
    $origin = if ($isUrl) { ConvertTo-WingetFWLogText (Get-WingetFWModUri -Root $Root -RelativePath $RelativePath) } else { Join-Path -Path $Root -ChildPath $RelativePath }
    $notFound = @{ Status = 'NotFound'; Bytes = $null; Origin = $origin }

    if ($SyncMode -eq 'Mirror')
    {
        if (-not (Test-Path -LiteralPath $cacheFile -PathType Leaf)) { return $notFound }
        return @{ Status = 'Found'; Bytes = [IO.File]::ReadAllBytes($cacheFile); Origin = $origin }
    }
    if ($isUrl)
    {
        $status = Invoke-WingetFWDownload -Uri (Get-WingetFWModUri -Root $Root -RelativePath $RelativePath) -OutFile $cacheFile
        if ($status -eq 'Found') { return @{ Status = 'Found'; Bytes = [IO.File]::ReadAllBytes($cacheFile); Origin = $origin } }
        if ($status -eq 'NotFound') { Remove-Item -LiteralPath $cacheFile -Force -ErrorAction SilentlyContinue; return $notFound }
        return @{ Status = 'Unreachable'; Bytes = $null; Origin = $origin }
    }
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @{ Status = 'Unreachable'; Bytes = $null; Origin = $origin } }
    if (-not (Test-Path -LiteralPath $origin -PathType Leaf))
    {
        Remove-Item -LiteralPath $cacheFile -Force -ErrorAction SilentlyContinue
        return $notFound
    }
    # Read once; the same bytes are checked, cached and loaded
    $bytes = [IO.File]::ReadAllBytes($origin)
    $cacheFolder = Split-Path -Path $cacheFile -Parent
    if (-not (Test-Path -LiteralPath $cacheFolder -PathType Container)) { $null = New-Item -Path $cacheFolder -ItemType Directory -Force }
    [IO.File]::WriteAllBytes($cacheFile, $bytes)
    @{ Status = 'Found'; Bytes = $bytes; Origin = $origin }
}

function ConvertTo-WingetFWMod
{
    # Signature check, load check and loading of one mod file.
    param ([byte[]]$Bytes, [string]$Origin, [string]$Name, [string]$RequireSigned, [string[]]$TrustedSigners)

    if ($RequireSigned -ne 'Off')
    {
        # Get-AuthenticodeSignature -Content only accepts UTF-16 text, so the same bytes are checked from a temp file
        $tempFile = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ('WingetFW-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
        try
        {
            [IO.File]::WriteAllBytes($tempFile, $Bytes)
            $signature = Get-AuthenticodeSignature -LiteralPath $tempFile
        }
        finally
        {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
        if ($signature.Status -ne 'Valid') { throw "Mod file [$Origin] is not validly signed ($($signature.Status)). RequireSignedScripts is $RequireSigned." }
        $thumbprint = $signature.SignerCertificate.Thumbprint
        if ($RequireSigned -eq 'TrustedSigners' -and $thumbprint -notin $TrustedSigners)
        {
            throw "Mod file [$Origin] is signed by [$($signature.SignerCertificate.Subject)] ($thumbprint), which is not in TrustedSigners."
        }
        Write-WingetFWLog -Message "Mod file [$Origin] is signed by [$($signature.SignerCertificate.Subject)] ($thumbprint)" -Source 'Import-WingetFWMod'
    }

    $reader = New-Object -TypeName IO.StreamReader -ArgumentList (New-Object -TypeName IO.MemoryStream -ArgumentList (, $Bytes)), (New-Object -TypeName Text.UTF8Encoding -ArgumentList $false), $true
    try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw "Mod file [$Origin] has a syntax error on line $($parseErrors[0].Extent.StartLineNumber): $($parseErrors[0].Message)" }
    if ($ast.UsingStatements.Count -or $ast.ParamBlock -or $ast.BeginBlock -or $ast.ProcessBlock -or $ast.DynamicParamBlock)
    {
        throw "Mod file [$Origin] is refused: only function definitions and `$Settings are allowed (no using, param, begin or process blocks)."
    }
    $settings = @{}
    $functions = New-Object -TypeName System.Collections.Generic.List[string]
    $hasSettings = $false
    foreach ($statement in @($ast.EndBlock.Statements))
    {
        if ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst])
        {
            $functions.Add($statement.Name)
            continue
        }
        $isSettings = $statement -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $statement.Operator -eq 'Equals' -and
            $statement.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $statement.Left.VariablePath.UserPath -eq 'Settings' -and
            $statement.Right -is [System.Management.Automation.Language.CommandExpressionAst] -and
            $statement.Right.Expression -is [System.Management.Automation.Language.HashtableAst]
        if (-not $isSettings -or $hasSettings)
        {
            throw "Mod file [$Origin] is refused: line $($statement.Extent.StartLineNumber) runs code when the file is loaded. Only function definitions and one `$Settings = @{ ... } are allowed at the top level."
        }
        try
        {
            $settings = $statement.Right.Expression.SafeGetValue()
        }
        catch
        {
            throw "Mod file [$Origin] is refused: `$Settings on line $($statement.Extent.StartLineNumber) may only contain fixed values ($($_.Exception.Message))."
        }
        $hasSettings = $true
    }

    $module = New-Object -TypeName System.Management.Automation.PSModuleInfo -ArgumentList ([scriptblock]::Create($text))
    Write-WingetFWLog -Message "Loaded $Name mod [$Origin] with sections: $(@($functions) -join ', ')" -Source 'Import-WingetFWMod'
    [pscustomobject]@{ Name = $Name; Origin = $Origin; Settings = $settings; Functions = $functions.ToArray(); Module = $module }
}

function Import-WingetFWMod
{
    <#
    .SYNOPSIS
        Finds, fetches, checks and loads the global mod file and the app mod file.
    .DESCRIPTION
        Files: <ScriptRoot>\_WingetFW.ps1 (global) and <ScriptRoot>\<Source>\<Id>.ps1 (app). Each ScriptRoot (local folder,
        UNC share or Azure blob container URL with SAS) is searched in order; the first one with the file wins.
        Settings used: ScriptRoot (default: <PackagePath>\Mods), ScriptSyncMode (OnDemand, Mirror), UseCachedScriptsWhenOffline,
        AllowedScriptSources (default: <PackagePath> and ProgramData\WingetFW\Scripts), RequireSignedScripts (Off, Signed,
        TrustedSigners) and TrustedSigners.
        A ScriptRoot that is not allowed, a root that can't be reached (without the cache option), a bad signature or a file
        that runs code when it is loaded throws an error.
        Returns an object with Global and App; each is $null or a mod with Name, Origin, Settings, Functions and Module.
    .PARAMETER Id
        Package ID for the app mod. Empty: only the global mod.
    .PARAMETER Source
        winget source, the folder of the app mod.
    .PARAMETER Scope
        Machine: cache in ProgramData\WingetFW\Cache (needs administrator rights). User: LOCALAPPDATA\WingetFW\Cache.
    .PARAMETER Config
        Settings from the package config file.
    .PARAMETER PackagePath
        Package folder, used for the default ScriptRoot and AllowedScriptSources.
    .PARAMETER CacheRoot
        Other cache folder (tests).
    .PARAMETER PolicyPath
        Policy registry key (tests).
    .PARAMETER LocalPath
        Local registry key (tests).
    .EXAMPLE
        $mods = Import-WingetFWMod -Id '7zip.7zip' -Source 'winget' -Config $config -PackagePath 'C:\Package'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param
    (
        [Parameter()]
        [AllowEmptyString()]
        [string]$Id,

        [Parameter()]
        [string]$Source = 'winget',

        [Parameter()]
        [ValidateSet('Machine', 'User')]
        [string]$Scope = 'Machine',

        [Parameter()]
        [System.Collections.IDictionary]$Config = @{},

        [Parameter(Mandatory = $true)]
        [string]$PackagePath,

        [Parameter()]
        [string]$CacheRoot,

        [Parameter()]
        [string]$PolicyPath = 'HKLM:\SOFTWARE\Policies\WingetFW',

        [Parameter()]
        [string]$LocalPath = 'HKLM:\SOFTWARE\WingetFW'
    )

    $settingParams = @{ Config = $Config; PolicyPath = $PolicyPath; LocalPath = $LocalPath }
    $roots = @((Get-WingetFWSetting -Name 'ScriptRoot' -Default @(Join-Path -Path $PackagePath -ChildPath 'Mods') @settingParams).Value | Where-Object { $_ })
    $syncMode = [string](Get-WingetFWSetting -Name 'ScriptSyncMode' -Default 'OnDemand' @settingParams).Value
    if ($syncMode -notin @('OnDemand', 'Mirror')) { throw "ScriptSyncMode [$syncMode] is not valid. Use OnDemand or Mirror." }
    $useCache = (Get-WingetFWSetting -Name 'UseCachedScriptsWhenOffline' -Default $false -AsBoolean @settingParams).Value
    $requireSigned = [string](Get-WingetFWSetting -Name 'RequireSignedScripts' -Default 'Off' @settingParams).Value
    if ($requireSigned -notin @('Off', 'Signed', 'TrustedSigners')) { throw "RequireSignedScripts [$requireSigned] is not valid. Use Off, Signed or TrustedSigners." }
    $trustedSigners = @(@((Get-WingetFWSetting -Name 'TrustedSigners' @settingParams).Value) | Where-Object { $_ } | ForEach-Object { ([string]$_ -replace '\s', '').ToUpperInvariant() })
    if ($requireSigned -eq 'TrustedSigners' -and -not $trustedSigners.Count) { throw 'RequireSignedScripts is TrustedSigners, but TrustedSigners is empty.' }
    $allowed = @((Get-WingetFWSetting -Name 'AllowedScriptSources' -Default @($PackagePath, (Join-Path -Path $env:ProgramData -ChildPath 'WingetFW\Scripts')) @settingParams).Value)

    foreach ($root in $roots)
    {
        if (-not (Test-WingetFWAllowedLocation -Location $root -Allowed $allowed))
        {
            throw "ScriptRoot [$(ConvertTo-WingetFWLogText $root)] is not in AllowedScriptSources."
        }
        if ($root -match '^http://') { Write-WingetFWLog -Message "ScriptRoot [$(ConvertTo-WingetFWLogText $root)] uses http, not https" -Severity 2 -Source 'Import-WingetFWMod' }
    }

    $idPattern = '^(?!\.{1,2}$)[^\\/:*?"<>|\x00-\x1f]+$'
    $wanted = @(@{ Name = 'Global'; Relative = '_WingetFW.ps1' })
    if ($Id)
    {
        if ($Id -notmatch $idPattern -or $Source -notmatch $idPattern) { throw "Package ID [$Id] or source [$Source] can't be used as a mod file name." }
        $wanted += @{ Name = 'App'; Relative = "$Source\$Id.ps1" }
    }

    if (-not $CacheRoot)
    {
        if ($Scope -eq 'Machine')
        {
            $machineRoot = Get-WingetFWRoot -Scope 'Machine'
            Protect-WingetFWFolder -Path $machineRoot
            $CacheRoot = Join-Path -Path $machineRoot -ChildPath 'Cache'
            Protect-WingetFWFolder -Path $CacheRoot -NoUsers
        }
        else
        {
            $CacheRoot = Join-Path -Path (Get-WingetFWRoot -Scope 'User') -ChildPath 'Cache'
        }
    }

    $result = [ordered]@{ Global = $null; App = $null }
    foreach ($root in $roots)
    {
        $logRoot = ConvertTo-WingetFWLogText $root
        $cacheDir = Join-Path -Path $CacheRoot -ChildPath (Get-WingetFWCacheName -Root $root)
        if ($syncMode -eq 'Mirror' -and -not (Sync-WingetFWModRoot -Root $root -CacheDir $cacheDir))
        {
            if (-not $useCache) { throw "ScriptRoot [$logRoot] can't be reached and UseCachedScriptsWhenOffline is off." }
            Write-WingetFWLog -Message "ScriptRoot [$logRoot] can't be reached, using the cached copy" -Severity 2 -Source 'Import-WingetFWMod'
        }
        foreach ($file in $wanted)
        {
            if ($result[$file.Name]) { continue }
            $found = Get-WingetFWModFromRoot -Root $root -RelativePath $file.Relative -CacheDir $cacheDir -SyncMode $syncMode
            if ($found.Status -eq 'Unreachable')
            {
                if (-not $useCache) { throw "ScriptRoot [$logRoot] can't be reached and UseCachedScriptsWhenOffline is off." }
                $cacheFile = Join-Path -Path $cacheDir -ChildPath $file.Relative
                if (-not (Test-Path -LiteralPath $cacheFile -PathType Leaf)) { continue }
                Write-WingetFWLog -Message "ScriptRoot [$logRoot] can't be reached, using the cached copy of [$($file.Relative)]" -Severity 2 -Source 'Import-WingetFWMod'
                $found = @{ Status = 'Found'; Bytes = [IO.File]::ReadAllBytes($cacheFile); Origin = "$($found.Origin) (cached copy)" }
            }
            if ($found.Status -eq 'Found')
            {
                $result[$file.Name] = ConvertTo-WingetFWMod -Bytes $found.Bytes -Origin $found.Origin -Name $file.Name -RequireSigned $requireSigned -TrustedSigners $trustedSigners
            }
        }
    }
    foreach ($file in $wanted)
    {
        if (-not $result[$file.Name]) { Write-WingetFWLog -Message "No $($file.Name.ToLower()) mod file ($($file.Relative))" -Source 'Import-WingetFWMod' }
    }
    [pscustomobject]$result
}

function Invoke-WingetFWModSection
{
    <#
    .SYNOPSIS
        Runs one section (function) of a mod file, for example PreInstall. Does nothing when the mod has no such section.
    .DESCRIPTION
        The section runs in the mod's own scope and can use $WingetFW (the -Context object).
        Returns $false when the section returned $false, $true when it ran, and nothing when the mod has no such section.
    .PARAMETER Mod
        A mod from Import-WingetFWMod.
    .PARAMETER Section
        Function name, for example PreInstall, Install, PostInstall, NotInstalled.
    .PARAMETER Context
        Object the section sees as $WingetFW, for example Action, Id, Source, ExitCode.
    .EXAMPLE
        Invoke-WingetFWModSection -Mod $mods.App -Section 'PreInstall' -Context $context
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [psobject]$Mod,

        [Parameter(Mandatory = $true)]
        [string]$Section,

        [Parameter()]
        [psobject]$Context
    )

    if ($Mod.Functions -notcontains $Section) { return }
    Write-WingetFWLog -Message "Running [$Section] from the $($Mod.Name.ToLower()) mod [$($Mod.Origin)]" -Source 'Invoke-WingetFWModSection'
    $output = @(& $Mod.Module { param ($sectionName, $sectionContext) $script:WingetFW = $sectionContext; & $sectionName } $Section $Context)
    if ($output.Count -and $output[-1] -is [bool] -and -not $output[-1])
    {
        Write-WingetFWLog -Message "[$Section] from the $($Mod.Name.ToLower()) mod returned `$false" -Source 'Invoke-WingetFWModSection'
        return $false
    }
    $true
}

#endregion

Export-ModuleMember -Function 'Get-WingetFWSetting', 'Write-WingetFWLog', 'Register-WingetFWEventLog', 'Write-WingetFWEvent', 'Get-WingetFWState', 'Set-WingetFWState', 'Import-WingetFWMod', 'Invoke-WingetFWModSection'
