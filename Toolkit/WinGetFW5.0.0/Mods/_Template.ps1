<#
.SYNOPSIS
    WingetFW mod file template.

.DESCRIPTION
    Copy this file to <ScriptRoot>\<source>\<package id>.ps1 for one app, for example
    \\fs01\WingetFW\Mods\winget\7zip.7zip.ps1, or to <ScriptRoot>\_WingetFW.ps1 for every app.
    Keep only the sections you need.

    Rules (the file is refused when they are broken, exit code 60001):
    - Only function definitions and one $Settings = @{ ... } at the top level. No other code.
    - $Settings may only contain fixed values: text, numbers, $true/$false, @( ... ) and @{ ... }.
    - $Settings is only read from the app mod file, not from _WingetFW.ps1.

    How the sections run:
    - Order: global Pre, app Pre, winget, app During, global During, app Post or Not, global Post or Not.
    - Pre (PreInstall ...) runs before winget. Return $false to skip the action: exit code 69002.
    - During (Install, Uninstall, Repair, Upgrade) runs after winget, before the result is checked.
    - Post (PostInstall ...) runs when winget succeeded, Not (NotInstalled ...) when it failed.
    - -ForceRepair runs winget uninstall and install between the Repair sections.
    - The global file can also have PreImport and PostImport.
    - Sections run inside the WingetFW deployment: PSAppDeployToolkit functions work, for example
      Write-ADTLogEntry, Show-ADTInstallationWelcome, Set-ADTRegistryKey, Remove-ADTFile.
    - $WingetFW has Action, Id, Source, UserMode, ForceRepair, Parameters, and after winget ExitCode and Success.
    - An error in a section stops the deployment with exit code 60001.

.NOTES
    Maintained by: KSKITDK
    Version      : 1.0.0

    Release notes
    1.0.0  - First version.

.LINK
    https://github.com/ksk-itdk/PSADT-WingetFW
#>

# Settings per action. Same names and rules as the command line; the command line beats them.
# Also possible here: DefaultSilent, DefaultSource, Proxy (see Docs\Configuration.md).
$Settings = @{
    Install   = @{
        # Override         = '/S'
        # Custom           = 'REBOOT=ReallySuppress'
        # Scope            = 'Machine'
        # Locale           = 'en-US'
        # Architecture     = 'X64'
        # Source           = 'winget'
        # SkipDependencies = $true
    }
    Uninstall = @{}
    Repair    = @{}
    Upgrade   = @{}
}

##================================================
## MARK: Install
##================================================
function PreInstall
{
    # Example: close the app first.
    # Show-ADTInstallationWelcome -CloseProcesses @{ Name = '7zFM' } -Silent

    # Example: remove a conflicting app first (nothing happens when it is not installed).
    # Uninstall-ADTApplication -Name 'Contoso Viewer*' -NameMatch Wildcard -ArgumentList '/S'
    # Uninstall-ADTApplication -ProductCode '{26A24AE4-039D-4CA4-87B4-2F64180451F0}'
}

function Install
{
    # Runs after winget install, before the result is checked. $WingetFW.ExitCode has the winget exit code.
}

function PostInstall
{
    # Example: a setting the installer does not set.
    # Set-ADTRegistryKey -LiteralPath 'HKLM:\SOFTWARE\Contoso\App' -Name 'AutoUpdate' -Value 0 -Type DWord
}

function NotInstalled
{
    # Example: log more details.
    # Write-ADTLogEntry -Message "Install of $($WingetFW.Id) failed with $($WingetFW.ExitCode)" -Severity 2
}

##================================================
## MARK: Uninstall
##================================================
function PreUninstall
{
}

function Uninstall
{
}

function PostUninstall
{
    # Example: remove files the uninstaller leaves behind.
    # Remove-ADTFolder -Path "$env:ProgramFiles\Contoso\App"
}

function NotUninstalled
{
}

##================================================
## MARK: Repair
##================================================
function PreRepair
{
}

function Repair
{
}

function PostRepair
{
}

function NotRepaired
{
}

##================================================
## MARK: Upgrade
##================================================
function PreUpgrade
{
}

function Upgrade
{
}

function PostUpgrade
{
}

function NotUpgraded
{
}
