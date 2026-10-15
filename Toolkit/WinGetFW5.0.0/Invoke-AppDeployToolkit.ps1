<#

.SYNOPSIS
PSAppDeployToolkit - This script performs the installation or uninstallation of an application(s).

.DESCRIPTION
- The script is provided as a template to perform an install, uninstall, or repair of an application(s).
- The script either performs an "Install", "Uninstall", or "Repair" deployment type.
- The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.

The script imports the PSAppDeployToolkit module which contains the logic and functions required to install or uninstall an application.

.PARAMETER DeploymentType
The type of deployment to perform.

.PARAMETER DeployMode
Specifies whether the installation should be run in Interactive (shows dialogs), Silent (no dialogs), NonInteractive (dialogs without prompts) mode, or Auto (shows dialogs if a user is logged on, device is not in the OOBE, and there's no running apps to close).

Silent mode is automatically set if it is detected that the process is not user interactive, no users are logged on, the device is in Autopilot mode, or there's specified processes to close that are currently running.

.PARAMETER SuppressRebootPassThru
Suppresses the 3010 return code (requires restart) from being passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.

.PARAMETER TerminalServerMode
Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Desktop Session Hosts/Citrix servers.

.PARAMETER DisableLogging
Disables logging to file for the script.

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1 -DeployMode Silent

.EXAMPLE
powershell.exe -File Invoke-AppDeployToolkit.ps1 -DeploymentType Uninstall

.EXAMPLE
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent

.INPUTS
None. You cannot pipe objects to this script.

.OUTPUTS
None. This script does not generate any output.

.NOTES
Toolkit Exit Code Ranges:
- 60000 - 68999: Reserved for built-in exit codes in Invoke-AppDeployToolkit.ps1, and Invoke-AppDeployToolkit.exe
- 69000 - 69999: Recommended for user customized exit codes in Invoke-AppDeployToolkit.ps1
- 70000 - 79999: Recommended for user customized exit codes in PSAppDeployToolkit.Extensions module.

.LINK
https://psappdeploytoolkit.com

#>

[CmdletBinding()]
param
(
    # Default is 'Install'.
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [System.String]$DeploymentType,

    # Default is 'Auto'. Don't hard-code this unless required.
    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'Interactive', 'NonInteractive', 'Silent')]
    [System.String]$DeployMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$SuppressRebootPassThru,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$TerminalServerMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$DisableLogging,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Admin', 'User')]
    [String]$Mode = 'Admin',
    [Parameter( Mandatory = $false, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.')]
    [ValidateSet('Install', 'Uninstall', 'upgrade', 'import', 'Repair')]
    [String]$Action,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Must be followed by the path to the manifest (YAML) file. You can use the manifest to run the install experience from a local YAML file.')]
    [String]$wingetmanifest,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Limits the install to the ID of the application.')]
    [String]$id,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Limits the search to the name of the application.')]
    [String]$name,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Limits the search to the moniker listed for the application.')]
    [String]$moniker,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.')]
    [String]$version,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.')]
    [String]$source,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.')]
    [ValidateSet('User', 'Machine')]
    [String]$scope,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Select the architecture to install.')]
    [ValidateSet('Default', 'X86', 'Arm', 'X64', 'Arm64')]
    [String]$architecture,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.')]
    [ValidateSet('Default', 'Inno', 'Wix', 'Msi', 'Nullsoft', 'Zip', 'Msix', 'Exe', 'Burn', 'MSStore', 'Portable')]
    [String]$installertype,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.')]
    [Switch]$exact,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Runs the installer in interactive mode. The default experience shows installer progress.')]
    [Switch]$interactive,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Runs the installer in silent mode. This suppresses all UI. The default experience shows installer progress.')]
    [Switch]$silent,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Specifies which locale to use (BCP47 format).')]
    [String]$locale,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.')]
    [String]$log,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.')]
    [String]$custom,
    
    [Parameter( Mandatory = $false, HelpMessage = 'A string that will be passed directly to the installer.')]
    [String]$override,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Location to install to (if supported).')]
    [String]$location,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Ignore the installer hash check failure. Not recommended.')]
    [Switch]$ignoresecurityhash,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Allows a reboot if applicable.')]
    [Switch]$allowreboot,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Skips processing package dependencies and Windows features.')]
    [Switch]$skipdependencies,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.')]
    [Switch]$ignorelocalarchivemalwarescan,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Find package dependencies using the specified source.')]
    [String]$dependencysource,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.')]
    [Switch]$acceptpackageagreements = $true,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Skips upgrade if an installed version already exists.')]
    [Switch]$noupgrade,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.')]
    [String]$header,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).')]
    [ValidateSet('silent', 'silentPreferred', 'interactive')]
    [String]$authenticationmode,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Specify the account to be used for authentication.')]
    [String]$authenticationaccount,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.')]
    [Switch]$acceptsourceagreements = $true,
    
    [Parameter( Mandatory = $false, HelpMessage = 'The value to rename the executable file (portable).')]
    [String]$rename,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Uninstall the previous version of the package during upgrade.')]
    [Switch]$uninstallprevious,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Direct run the command and continue with non security related issues.')]
    [Switch]$force,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Used to override the logging setting and create a verbose log.')]
    [Switch]$enableverbose,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Suppresses warning outputs.')]
    [Switch]$ignorewarnings,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Disable interactive prompts.')]
    [Switch]$disableinteractivity,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Set a proxy to use for this execution.')]
    [String]$proxy,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Disable the use of proxy for this execution.')]
    [Switch]$noproxy,
    
    [Parameter( Mandatory = $false, HelpMessage = 'JSON file describing the packages to install (import).')]
    [String]$importfile,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Suppresses errors if the app requested is unavailable (import).')]
    [Switch]$ignoreunavailable,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Ignores versions specified in the JSON file and installs the latest available version (import).')]
    [Switch]$ignoreversions,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Filters using the product code (uninstall, repair).')]
    [String]$productcode,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Uninstall all versions (uninstall).')]
    [Switch]$allversions,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Deletes all files and directories in the package directory (portable) (uninstall, upgrade).')]
    [Switch]$purge,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Retains all files and directories created by the package (portable) (uninstall).')]
    [Switch]$preserve,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Upgrade packages even if their current version cannot be determined (upgrade).')]
    [Switch]$includeunknown,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Upgrade packages even if they have a non-blocking pin (upgrade).')]
    [Switch]$includepinned,
    
    [Parameter( Mandatory = $false, HelpMessage = 'Will override ID or Name use for the UI and the log')]
    [String]$OverrideAPPName,
    
    [Parameter( Mandatory = $false, HelpMessage = 'With -DeploymentType Repair: uninstall and install the package again instead of winget repair')]
    [Switch]$ForceRepair
)


##================================================
## MARK: Variables
##================================================

# Zero-Config MSI support is provided when "AppName" is null or empty.
# By setting the "AppName" property, Zero-Config MSI will be disabled.
$adtSession = @{
    # App variables.
    AppVendor = $(If(-NOT([string]::IsNullOrEmpty($OverrideAPPName))){$OverrideAPPName}elseif(-NOT([string]::IsNullOrEmpty($id))){$id}elseif(-NOT([string]::IsNullOrEmpty($name))){$name})
    AppName = 'WingetFW'
    AppVersion = '5.0.0'
    AppArch = ''
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @()  # Example: @('excel', @{ Name = 'winword'; Description = 'Microsoft Word' })
    AppScriptVersion = '1.0.0'
    AppScriptDate = '2026-10-14'
    AppScriptAuthor = 'Kris Spangenberg'
    RequireAdmin = $false

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName = ''
    InstallTitle = ''

    # Script variables.
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters = $PSBoundParameters
    DeployAppScriptVersion = '4.1.8'
}

##================================================
## MARK: WingetFW parameters
##================================================

# -Action follows -DeploymentType unless set (upgrade, import)
If (!$Action) { $Action = If ($DeploymentType) { $DeploymentType } Else { 'Install' } }
$parWinGet = $null
$parWinGet = @{}
Switch ($scope) {
	'User' {
		$parWinGet.Add("scope", "user")
	}
	'Machine' {
		$parWinGet.Add("scope", "machine")
	}
}

Switch ($architecture) {
	'Default' {
		
	}
	'X86' {
		$parWinGet.Add("architecture", "x86")
	}
	'Arm' {
		$parWinGet.Add("architecture", "arm")
	}
	'X64' {
		$parWinGet.Add("architecture", "x64")
	}
	'Arm64' {
		$parWinGet.Add("architecture", "arm64")
	}
}

Switch ($installertype) {
	'Default' {
		
	}
	'Inno' {
		$parWinGet.Add("installertype", "inno")
	}
	'Wix' {
		$parWinGet.Add("installertype", "wix")
	}
	'Msi' {
		$parWinGet.Add("installertype", "msi")
	}
	'Nullsoft' {
		$parWinGet.Add("installertype", "nullsoft")
	}
	'Zip' {
		$parWinGet.Add("installertype", "zip")
	}
	'Msix' {
		$parWinGet.Add("installertype", "msix")
	}
	'Exe' {
		$parWinGet.Add("installertype", "exe")
	}
	'Burn' {
		$parWinGet.Add("installertype", "burn")
	}
	'MSStore' {
		$parWinGet.Add("installertype", "msstore")
	}
	'Portable' {
		$parWinGet.Add("installertype", "portable")
	}
}

Switch ($authenticationmode) {
	'silent' {
		$parWinGet.Add("authenticationmode", "silent")
	}
	'silentPreferred' {
		$parWinGet.Add("authenticationmode", "silentPreferred")
	}
	'interactive' {
		$parWinGet.Add("authenticationmode", "interactive")
	}
}

If ($wingetmanifest) {
	$parWinGet.Add("wingetmanifest", $wingetmanifest)
}
If ($id) {
	$parWinGet.Add("id", $id)
}
If ($name) {
	$parWinGet.Add("name", $name)
}
If ($moniker) {
	$parWinGet.Add("moniker", $moniker)
}
If ($version) {
	$parWinGet.Add("version", $version)
}
If ($source) {
	$parWinGet.Add("source", $source)
}
If ($exact) {
	$parWinGet.Add("exact", $true)
}else{
	$parWinGet.Add("exact", $false)
}
If ($interactive) {
	$parWinGet.Add("interactive", $true)
}else{
	$parWinGet.Add("interactive", $false)
}
If ($silent) {
	$parWinGet.Add("silent", $true)
}else{
	$parWinGet.Add("silent", $false)
}
If ($locale) {
	$parWinGet.Add("locale", $locale)
}
If ($log) {
	$parWinGet.Add("log", $log)
}
If ($custom) {
	$parWinGet.Add("custom", $custom)
}
If ($override) {
	$parWinGet.Add("override", $override)
}
If ($location) {
	Write-Verbose "location: $($location)"
	if(($location -notmatch [char]39)-and($location -notmatch [char]34)){
		$parWinGet.Add("location", [char]34 + $location + [char]34)
	}else{
		$parWinGet.Add("location", $location)
	}
}
If ($ignoresecurityhash) {
	$parWinGet.Add("ignoresecurityhash", $true)
}else{
	$parWinGet.Add("ignoresecurityhash", $false)
}
If ($allowreboot) {
	$parWinGet.Add("allowreboot", $true)
}else{
	$parWinGet.Add("allowreboot", $false)
}
If ($skipdependencies) {
	$parWinGet.Add("skipdependencies", $true)
}else{
	$parWinGet.Add("skipdependencies", $false)
}
If ($ignorelocalarchivemalwarescan) {
	$parWinGet.Add("ignorelocalarchivemalwarescan", $true)
}else{
	$parWinGet.Add("ignorelocalarchivemalwarescan", $false)
}
If ($dependencysource) {
	$parWinGet.Add("dependencysource", $dependencysource)
}
If (($($PSBoundParameters.Keys) -Match 'acceptpackageagreements')-OR($Action -NE 'Uninstall')){
	Write-Verbose "PSBoundParameters -Match acceptpackageagreements)"
	If ($acceptpackageagreements) {
		$parWinGet.Add("acceptpackageagreements", $true)
	}else{
		$parWinGet.Add("acceptpackageagreements", $false)
	}
}else{
	Write-Verbose "PSBoundParameters -Notmatch acceptpackageagreements)"
	$parWinGet.Add("acceptpackageagreements", $false)
}
If ($noupgrade) {
	$parWinGet.Add("noupgrade", $true)
}else{
	$parWinGet.Add("noupgrade", $false)
}
If ($header) {
	$parWinGet.Add("header", $header)
}
If ($authenticationaccount) {
	$parWinGet.Add("authenticationaccount", $authenticationaccount)
}
If (($($PSBoundParameters.Keys) -Match 'acceptsourceagreements')-OR($Action -NE 'Uninstall')){
	Write-Verbose "PSBoundParameters -Match acceptsourceagreements)"
	If ($acceptsourceagreements) {
		$parWinGet.Add("acceptsourceagreements", $true)
	}else{
		$parWinGet.Add("acceptsourceagreements", $false)
	}
}else{
	Write-Verbose "PSBoundParameters -Notmatch acceptsourceagreements)"
	$parWinGet.Add("acceptsourceagreements", $false)
}
If ($rename) {
	$parWinGet.Add("rename", $rename)
}
If ($uninstallprevious) {
	$parWinGet.Add("uninstallprevious", $true)
}else{
	$parWinGet.Add("uninstallprevious", $false)
}
If ($force) {
	$parWinGet.Add("force", $true)
}else{
	$parWinGet.Add("force", $false)
}
If ($enableverbose) {
	$parWinGet.Add("enableverbose", $true)
}else{
	$parWinGet.Add("enableverbose", $false)
}
If ($ignorewarnings) {
	$parWinGet.Add("ignorewarnings", $true)
}else{
	$parWinGet.Add("ignorewarnings", $false)
}
If ($disableinteractivity) {
	$parWinGet.Add("disableinteractivity", $true)
}else{
	$parWinGet.Add("disableinteractivity", $false)
}
If ($proxy) {
	$parWinGet.Add("proxy", $proxy)
}
If ($noproxy) {
	$parWinGet.Add("noproxy", $true)
}else{
	$parWinGet.Add("noproxy", $false)
}
If ($importfile) {
	$parWinGet.Add("importfile", $importfile)
}
If ($ignoreunavailable) {
	$parWinGet.Add("ignoreunavailable", $true)
}else{
	$parWinGet.Add("ignoreunavailable", $false)
}
If ($ignoreversions) {
	$parWinGet.Add("ignoreversions", $true)
}else{
	$parWinGet.Add("ignoreversions", $false)
}
If ($productcode) {
	$parWinGet.Add("productcode", $productcode)
}
If ($allversions) {
	$parWinGet.Add("allversions", $true)
}else{
	$parWinGet.Add("allversions", $false)
}
If ($purge) {
	$parWinGet.Add("purge", $true)
}else{
	$parWinGet.Add("purge", $false)
}
If ($preserve) {
	$parWinGet.Add("preserve", $true)
}else{
	$parWinGet.Add("preserve", $false)
}
If ($includeunknown) {
	$parWinGet.Add("includeunknown", $true)
}else{
	$parWinGet.Add("includeunknown", $false)
}
If ($includepinned) {
	$parWinGet.Add("includepinned", $true)
}else{
	$parWinGet.Add("includepinned", $false)
}
$parWinGetText = ($parWinGet.GetEnumerator() | Where-Object { $_.Value -ne $false } | Sort-Object Key | ForEach-Object { If ($_.Value -eq $true) { "-$($_.Key)" } Else { "-$($_.Key) '$($_.Value)'" } }) -join ' '


function Install-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Install
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    ## Show Welcome Message, close processes if specified, allow up to 3 deferrals, verify there is enough disk space to complete the install, and persist the prompt.
    $saiwParams = @{
        AllowDefer = $true
        DeferTimes = 3
        CheckDiskSpace = $true
        PersistPrompt = $true
    }
	if ($adtSession.AppProcessesToClose.Count -gt 0){
		If(Test-ADTPowerPoint){
			Close-ADTSession -ExitCode 1618
		}
		$processfoundcount = 0
		foreach($apptoclose in ($adtSession.AppProcessesToClose).Name){
			If(Get-Process -ProcessName $apptoclose -ErrorAction SilentlyContinue){
				$processfoundcount += 1
			}
		}
		if($processfoundcount -gt 0){
			$saiwParams.Add('CloseProcesses', $adtSession.AppProcessesToClose)
			Show-ADTInstallationWelcome @saiwParams
			Show-ADTInstallationProgress
		}
    }
    #Show-ADTInstallationWelcome @saiwParams
	
    ## Show Progress Message (with the default message).
    #Show-ADTInstallationProgress
	
    ## <Perform Pre-Installation tasks here>
	Write-ADTLogEntry -Message "Mode $Mode" -Source 'Mode-Check'
	Write-ADTLogEntry -Message "parWinGet $parWinGetText" -Source 'parWinGet-Check'
	If($Mode -eq "Admin"){
		Write-ADTLogEntry -Message "Mode $Mode" -Source 'Mode'
		Install-WinGetFM -UserMode 'Admin' -InstallMethod 'Online' -MinimumVersion '2023.1005.18.0'
		$AppInstaller = Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq Microsoft.DesktopAppInstaller
	}
	If($Mode -eq "User"){
		Write-ADTLogEntry -Message "Mode $Mode" -Source 'Mode'
		Install-WinGetFM -UserMode 'User' -MinimumVersion '1.22.10582.0'
	}
	
	
    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType
	
    ## <Perform Installation tasks here>
	Write-ADTLogEntry -Message "Mode $Mode" -Source 'Mode'
	IF ($wingetmanifest -or $id -or $name -or $moniker -or $productcode -or $importfile){
		Write-ADTLogEntry -Message "Invoke-WinGetActionFM -UserMode $($Mode) -Action $($Action) $parWinGetText" -Source 'Invoke-WinGetActionFM'
		Invoke-WinGetActionFM -UserMode $Mode -Action $Action -WinGetParameters $parWinGet
	}Else{
		Write-ADTLogEntry -Message "No package specified. Use -id, -name, -moniker, -wingetmanifest, -productcode or -importfile" -Severity 3 -Source 'INSTALLATION'
		Close-ADTSession -ExitCode 69001
	}
	
	
    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"
	
    ## <Perform Post-Installation tasks here>
	
	
}

function Uninstall-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )
	
    ##================================================
    ## MARK: Pre-Uninstall
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"
	
	## Show Welcome Message, close processes if specified, allow up to 3 deferrals, verify there is enough disk space to complete the install, and persist the prompt.
    $saiwParams = @{
        AllowDefer = $true
        DeferTimes = 3
        CheckDiskSpace = $true
        PersistPrompt = $true
    }
	if ($adtSession.AppProcessesToClose.Count -gt 0){
		If(Test-ADTPowerPoint){
			Close-ADTSession -ExitCode 1618
		}
		$processfoundcount = 0
		foreach($apptoclose in ($adtSession.AppProcessesToClose).Name){
			If(Get-Process -ProcessName $apptoclose -ErrorAction SilentlyContinue){
				$processfoundcount += 1
			}
		}
		if($processfoundcount -gt 0){
			$saiwParams.Add('CloseProcesses', $adtSession.AppProcessesToClose)
			Show-ADTInstallationWelcome @saiwParams
			Show-ADTInstallationProgress
		}
    }
	
    ## Show Progress Message (with the default message).
    #Show-ADTInstallationProgress
	
    ## <Perform Pre-Uninstallation tasks here>
	Write-ADTLogEntry -Message "Mode $Mode" -Source 'Mode-Check'
	Write-ADTLogEntry -Message "parWinGet $parWinGetText" -Source 'parWinGet-Check'
	If($Mode -eq "Admin"){
		Write-ADTLogEntry -Message "Mode $Mode" -Source 'Mode'
		Install-WinGetFM -UserMode 'Admin' -InstallMethod 'Online' -MinimumVersion '2023.1005.18.0'
		$AppInstaller = Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq Microsoft.DesktopAppInstaller
	}
	If($Mode -eq "User"){
		Write-ADTLogEntry -Message "Mode $Mode" -Source 'Mode'
		Install-WinGetFM -UserMode 'User' -MinimumVersion '1.22.10582.0'
	}
	
	
    ##================================================
    ## MARK: Uninstall
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType
	
    ## <Perform Uninstallation tasks here>
	Write-ADTLogEntry -Message "Mode $Mode" -Source 'Mode'
	IF ($wingetmanifest -or $id -or $name -or $moniker -or $productcode -or $importfile){
		Write-ADTLogEntry -Message "Invoke-WinGetActionFM -UserMode $($Mode) -Action $($Action) $parWinGetText" -Source 'Invoke-WinGetActionFM'
		Invoke-WinGetActionFM -UserMode $Mode -Action $Action -WinGetParameters $parWinGet
	}Else{
		Write-ADTLogEntry -Message "No package specified. Use -id, -name, -moniker, -wingetmanifest, -productcode or -importfile" -Severity 3 -Source 'UNINSTALLATION'
		Close-ADTSession -ExitCode 69001
	}
	
	
    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"
	
    ## <Perform Post-Uninstallation tasks here>
}

function Repair-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )
	
    ##================================================
    ## MARK: Pre-Repair
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"
	
    ## Show Welcome Message, close processes if specified, allow up to 3 deferrals, verify there is enough disk space to complete the install, and persist the prompt.
    $saiwParams = @{
        AllowDefer = $true
        DeferTimes = 3
        CheckDiskSpace = $true
        PersistPrompt = $true
    }
	if ($adtSession.AppProcessesToClose.Count -gt 0){
		If(Test-ADTPowerPoint){
			Close-ADTSession -ExitCode 1618
		}
		$processfoundcount = 0
		foreach($apptoclose in ($adtSession.AppProcessesToClose).Name){
			If(Get-Process -ProcessName $apptoclose -ErrorAction SilentlyContinue){
				$processfoundcount += 1
			}
		}
		if($processfoundcount -gt 0){
			$saiwParams.Add('CloseProcesses', $adtSession.AppProcessesToClose)
			Show-ADTInstallationWelcome @saiwParams
			Show-ADTInstallationProgress
		}
    }
	
    ## Show Progress Message (with the default message).
    #Show-ADTInstallationProgress
	
    ## <Perform Pre-Repair tasks here>
	Write-ADTLogEntry -Message "Mode $Mode" -Source 'Mode-Check'
	Write-ADTLogEntry -Message "parWinGet $parWinGetText" -Source 'parWinGet-Check'
	
	
    ##================================================
    ## MARK: Repair
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType
	
    ## <Perform Repair tasks here>
	Write-ADTLogEntry -Message "Mode $Mode" -Source 'Mode'
	IF ($wingetmanifest -or $id -or $name -or $moniker -or $productcode -or $importfile){
		Write-ADTLogEntry -Message "Invoke-WinGetActionFM -UserMode $($Mode) -Action Repair -ForceRepair:$([Bool]$ForceRepair) $parWinGetText" -Source 'Invoke-WinGetActionFM'
		Invoke-WinGetActionFM -UserMode $Mode -Action 'Repair' -ForceRepair:$ForceRepair -WinGetParameters $parWinGet
	}Else{
		Write-ADTLogEntry -Message "No package specified. Use -id, -name, -moniker, -wingetmanifest, -productcode or -importfile" -Severity 3 -Source 'REPAIR'
		Close-ADTSession -ExitCode 69001
	}
	
	
    ##================================================
    ## MARK: Post-Repair
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"
	
    ## <Perform Post-Repair tasks here>
}


##================================================
## MARK: Initialization
##================================================

# Set strict error handling across entire operation.
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 1

# Import the module and instantiate a new session.
try
{
    # Import the module locally if available, otherwise try to find it from PSModulePath.
    if (Test-Path -LiteralPath "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1" -PathType Leaf)
    {
        Get-ChildItem -LiteralPath "$PSScriptRoot\PSAppDeployToolkit" -Recurse -File | Unblock-File -ErrorAction Ignore
        Import-Module -FullyQualifiedName @{ ModuleName = "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1"; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }
    else
    {
        Import-Module -FullyQualifiedName @{ ModuleName = 'PSAppDeployToolkit'; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }

    # Open a new deployment session, replacing $adtSession with a DeploymentSession.
    $iadtParams = Get-ADTBoundParametersAndDefaultValues -Invocation $MyInvocation
    # WingetFW: pass only the parameters Open-ADTSession knows, not the WingetFW ones
    $openADTSessionParams = (Get-Command -Name Open-ADTSession).Parameters.Keys
    @($iadtParams.Keys) | Where-Object { $_ -notin $openADTSessionParams } | ForEach-Object { $null = $iadtParams.Remove($_) }
    $adtSession = Remove-ADTHashtableNullOrEmptyValues -Hashtable $adtSession
    $adtSession = Open-ADTSession @adtSession @iadtParams -PassThru
}
catch
{
    $Host.UI.WriteErrorLine((Out-String -InputObject $_ -Width ([System.Int32]::MaxValue)))
    exit 60008
}


##================================================
## MARK: Invocation
##================================================

# Commence the actual deployment operation.
try
{
    # Import any found extensions before proceeding with the deployment.
    Get-ChildItem -LiteralPath $PSScriptRoot -Directory | & {
        process
        {
            if ($_.Name -match 'PSAppDeployToolkit\..+$')
            {
                Get-ChildItem -LiteralPath $_.FullName -Recurse -File | Unblock-File -ErrorAction Ignore
                Import-Module -Name $_.FullName -Force
            }
        }
    }

    # Invoke the deployment and close out the session.
    & "$($adtSession.DeploymentType)-ADTDeployment"
    Close-ADTSession
}
catch
{
    # An unhandled error has been caught.
    $mainErrorMessage = "An unhandled error within [$($MyInvocation.MyCommand.Name)] has occurred.`n$(Resolve-ADTErrorRecord -ErrorRecord $_)"
    Write-ADTLogEntry -Message $mainErrorMessage -Severity 3

    ## Error details hidden from the user by default. Show a simple dialog with full stack trace:
    # Show-ADTDialogBox -Text $mainErrorMessage -Icon Stop -NoWait

    ## Or, a themed dialog with basic error message:
    # Show-ADTInstallationPrompt -Message "$($adtSession.DeploymentType) failed at line $($_.InvocationInfo.ScriptLineNumber), char $($_.InvocationInfo.OffsetInLine):`n$($_.InvocationInfo.Line.Trim())`n`nMessage:`n$($_.Exception.Message)" -ButtonRightText OK -Icon Error -NoWait

    Close-ADTSession -ExitCode 60001
}

