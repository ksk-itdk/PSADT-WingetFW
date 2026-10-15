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

    Works in Windows PowerShell 5.1 and PowerShell 7.

.NOTES
    Maintained by: KSKITDK
    Version      : 1.0.0

    Release notes
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
    if (-not $item) { return }
    $value = $item.$Name
    # The comma keeps a REG_MULTI_SZ value as an array, also with one element.
    if ($value -is [array]) { , $value } else { $value }
}

function Protect-WingetFWFolder
{
    # SYSTEM and Administrators full control, Users read, owner Administrators, no inherited rules.
    param ([string]$Path)

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
    foreach ($rule in @(@($Script:SidSystem, 'FullControl'), @($Script:SidAdministrators, 'FullControl'), @($Script:SidUsers, 'ReadAndExecute')))
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
    .EXAMPLE
        Get-WingetFWSetting -Name 'DefaultSilent' -CommandLine $PSBoundParameters -Config $config -Default 1
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
        [string]$LocalPath = 'HKLM:\SOFTWARE\WingetFW'
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

    $text = if ($source -eq 'None') { '<not set>' } else { (@($value) -join '; ') -replace '(?i)(sig=)[^&;\s]+', '$1***' }
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

Export-ModuleMember -Function 'Get-WingetFWSetting', 'Write-WingetFWLog', 'Register-WingetFWEventLog', 'Write-WingetFWEvent', 'Get-WingetFWState', 'Set-WingetFWState'
