<#
.SYNOPSIS

PSApppDeployToolkit - This script performs the installation or uninstallation of an application(s).

.DESCRIPTION

- The script is provided as a template to perform an install or uninstall of an application(s).
- The script either performs an "Install" deployment type or an "Uninstall" deployment type.
- The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.

The script dot-sources the AppDeployToolkitMain.ps1 script which contains the logic and functions required to install or uninstall an application.

PSApppDeployToolkit is licensed under the GNU LGPLv3 License - (C) 2023 PSAppDeployToolkit Team (Sean Lillis, Dan Cunningham and Muhammad Mashwani).

This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the
Free Software Foundation, either version 3 of the License, or any later version. This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
for more details. You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.

.PARAMETER DeploymentType

The type of deployment to perform. Default is: Install.

.PARAMETER DeployMode

Specifies whether the installation should be run in Interactive, Silent, or NonInteractive mode. Default is: Interactive. Options: Interactive = Shows dialogs, Silent = No dialogs, NonInteractive = Very silent, i.e. no blocking apps. NonInteractive mode is automatically set if it is detected that the process is not user interactive.

.PARAMETER AllowRebootPassThru

Allows the 3010 return code (requires restart) to be passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.

.PARAMETER TerminalServerMode

Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Desktop Session Hosts/Citrix servers.

.PARAMETER DisableLogging

Disables logging to file for the script. Default is: $false.

.EXAMPLE

powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeployMode 'Silent'; Exit $LastExitCode }"

.EXAMPLE

powershell.exe -Command "& { & '.\Deploy-Application.ps1' -AllowRebootPassThru; Exit $LastExitCode }"

.EXAMPLE

powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeploymentType 'Uninstall'; Exit $LastExitCode }"

.EXAMPLE

Deploy-Application.exe -DeploymentType "Install" -DeployMode "Silent"

.INPUTS

None

You cannot pipe objects to this script.

.OUTPUTS

None

This script does not generate any output.

.NOTES

Toolkit Exit Code Ranges:
- 60000 - 68999: Reserved for built-in exit codes in Deploy-Application.ps1, Deploy-Application.exe, and AppDeployToolkitMain.ps1
- 69000 - 69999: Recommended for user customized exit codes in Deploy-Application.ps1
- 70000 - 79999: Recommended for user customized exit codes in AppDeployToolkitExtensions.ps1

.LINK

https://psappdeploytoolkit.com
#>


[CmdletBinding()]
Param (
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [String]$DeploymentType = 'Install',
    [Parameter(Mandatory = $false)]
    [ValidateSet('Interactive', 'Silent', 'NonInteractive')]
    [String]$DeployMode = 'Interactive',
    [Parameter(Mandatory = $false)]
    [switch]$AllowRebootPassThru = $false,
    [Parameter(Mandatory = $false)]
    [switch]$TerminalServerMode = $false,
    [Parameter(Mandatory = $false)]
    [switch]$DisableLogging = $false,
	[Parameter(Mandatory = $false)]
    [ValidateSet('Admin', 'User')]
    [String]$Mode = 'Admin',
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.')]
	[ValidateSet('Install', 'Uninstall', 'upgrade', 'import', 'Repair')]
	[String]$Action = $DeploymentType,
	
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

Try {
    ## Set the script execution policy for this process
    Try {
        Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop'
    }
    Catch {
    }

    ##*===============================================
    ##* VARIABLE DECLARATION
    ##*===============================================
    ## Variables: Application
    [String]$appVendor = $(If(-NOT([string]::IsNullOrEmpty($OverrideAPPName))){$OverrideAPPName}elseif(-NOT([string]::IsNullOrEmpty($id))){$id}elseif(-NOT([string]::IsNullOrEmpty($name))){$name})
    [String]$appName = 'WingetFW'
    [String]$appVersion = '4.0.7'
    [String]$appArch = ''
    [String]$appLang = 'EN'
    [String]$appRevision = '01'
    [String]$appScriptVersion = '1.0.0'
    [String]$appScriptDate = '27/04/2026'
    [String]$appScriptAuthor = 'Kris Spangenberg'
    ##*===============================================
    ## Variables: Install Titles (Only set here to override defaults set by the toolkit)
    [String]$installName = ''
    [String]$installTitle = ''

    ##* Do not modify section below
    #region DoNotModify

    ## Variables: Exit Code
    [Int32]$mainExitCode = 0

    ## Variables: Script
    [String]$deployAppScriptFriendlyName = 'Deploy Application'
    [Version]$deployAppScriptVersion = [Version]'3.9.3'
    [String]$deployAppScriptDate = '02/05/2023'
    [Hashtable]$deployAppScriptParameters = $PsBoundParameters

    ## Variables: Environment
    If (Test-Path -LiteralPath 'variable:HostInvocation') {
        $InvocationInfo = $HostInvocation
    }
    Else {
        $InvocationInfo = $MyInvocation
    }
    [String]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent

    ## Dot source the required App Deploy Toolkit Functions
    Try {
        [String]$moduleAppDeployToolkitMain = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
        If (-not (Test-Path -LiteralPath $moduleAppDeployToolkitMain -PathType 'Leaf')) {
            Throw "Module does not exist at the specified location [$moduleAppDeployToolkitMain]."
        }
        If ($DisableLogging) {
            . $moduleAppDeployToolkitMain -DisableLogging
        }
        Else {
            . $moduleAppDeployToolkitMain
        }
    }
    Catch {
        If ($mainExitCode -eq 0) {
            [Int32]$mainExitCode = 60008
        }
        Write-Error -Message "Module [$moduleAppDeployToolkitMain] failed to load: `n$($_.Exception.Message)`n `n$($_.InvocationInfo.PositionMessage)" -ErrorAction 'Continue'
        ## Exit the script, returning the exit code to SCCM
        If (Test-Path -LiteralPath 'variable:HostInvocation') {
            $script:ExitCode = $mainExitCode; Exit
        }
        Else {
            Exit $mainExitCode
        }
    }
	[String]$moduleAppDeployToolkitExtensions = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitExtensions.ps1"
	If ((Test-Path -LiteralPath $moduleAppDeployToolkitExtensions -PathType 'Leaf')) {
		. $moduleAppDeployToolkitExtensions
	}
	Write-Log -Message "Mode $Mode" -Source 'Mode-Check' -LogType 'CMTrace'
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
	Write-Log -Message "parWinGet $parWinGetText" -Source 'parWinGet-Check' -LogType 'CMTrace'

    #endregion
    ##* Do not modify section above
    ##*===============================================
    ##* END VARIABLE DECLARATION
    ##*===============================================

    If ($deploymentType -ine 'Uninstall' -and $deploymentType -ine 'Repair') {
        ##*===============================================
        ##* PRE-INSTALLATION
        ##*===============================================
        [String]$installPhase = 'Pre-Installation'
		
        ## Show Welcome Message, close Internet Explorer if required, allow up to 3 deferrals, verify there is enough disk space to complete the install, and persist the prompt
        #Show-InstallationWelcome -CloseApps 'iexplore' -AllowDefer -DeferTimes 3 -CheckDiskSpace -PersistPrompt
		
        ## Show Progress Message (with the default message)
        #Show-InstallationProgress
		
        ## <Perform Pre-Installation tasks here>
		If($Mode -eq "Admin"){
			Write-Log -Message "Mode $Mode" -Source 'Mode' -LogType 'CMTrace'
			Install-WinGetFM -UserMode 'Admin' -InstallMethod 'Online' -MinimumVersion '2023.1005.18.0'
			$AppInstaller = Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq Microsoft.DesktopAppInstaller
			
        }
		If($Mode -eq "User"){
			Write-Log -Message "Mode $Mode" -Source 'Mode' -LogType 'CMTrace'
            Install-WinGetFM -UserMode 'User' -MinimumVersion '1.22.10582.0'
        }
		
        ##*===============================================
        ##* INSTALLATION
        ##*===============================================
        [String]$installPhase = 'Installation'
		
        ## <Perform Installation tasks here>
		Write-Log -Message "Mode $Mode" -Source 'Mode' -LogType 'CMTrace'
		IF ($wingetmanifest -or $id -or $name -or $moniker -or $productcode -or $importfile){
				Write-Log -Message "Start-WinGetPackageFM -UserMode $($Mode) -Action $($Action) $parWinGetText" -Source 'Start-WinGetPackageFM' -LogType 'CMTrace'
				Start-WinGetPackageFM -UserMode $Mode -Action $Action @parWinGet

		}Else{
			Write-Log -Message "No package specified. Use -id, -name, -moniker, -wingetmanifest, -productcode or -importfile" -Severity 3 -Source 'INSTALLATION' -LogType 'CMTrace'
			Exit-Script -ExitCode 69001
		}
		
		
        ##*===============================================
        ##* POST-INSTALLATION
        ##*===============================================
        [String]$installPhase = 'Post-Installation'
		
        ## <Perform Post-Installation tasks here>
		
        
    }
    ElseIf ($deploymentType -ieq 'Uninstall') {
        ##*===============================================
        ##* PRE-UNINSTALLATION
        ##*===============================================
        [String]$installPhase = 'Pre-Uninstallation'
		
        ## Show Welcome Message, close Internet Explorer with a 60 second countdown before automatically closing
        #Show-InstallationWelcome -CloseApps 'iexplore' -CloseAppsCountdown 60
		
        ## Show Progress Message (with the default message)
        #Show-InstallationProgress
		
        ## <Perform Pre-Uninstallation tasks here>
		If($Mode -eq "Admin"){
			Write-Log -Message "Mode $Mode" -Source 'Mode' -LogType 'CMTrace'
			Install-WinGetFM -UserMode 'Admin' -InstallMethod 'Online' -MinimumVersion '2023.1005.18.0'
			$AppInstaller = Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq Microsoft.DesktopAppInstaller
			
        }
		If($Mode -eq "User"){
			Write-Log -Message "Mode $Mode" -Source 'Mode' -LogType 'CMTrace'
            Install-WinGetFM -UserMode 'User' -MinimumVersion '1.22.10582.0'
        }
		
        ##*===============================================
        ##* UNINSTALLATION
        ##*===============================================
        [String]$installPhase = 'Uninstallation'
		
        ## <Perform Uninstallation tasks here>
		Write-Log -Message "Mode $Mode" -Source 'Mode' -LogType 'CMTrace'
		IF ($wingetmanifest -or $id -or $name -or $moniker -or $productcode -or $importfile){
			Write-Log -Message "Start-WinGetPackageFM -UserMode $($Mode) -Action $($Action) $parWinGetText" -Source 'Start-WinGetPackageFM' -LogType 'CMTrace'
			Start-WinGetPackageFM -UserMode $Mode -Action $Action @parWinGet

		}Else{
			Write-Log -Message "No package specified. Use -id, -name, -moniker, -wingetmanifest, -productcode or -importfile" -Severity 3 -Source 'UNINSTALLATION' -LogType 'CMTrace'
			Exit-Script -ExitCode 69001
		}

		
        ##*===============================================
        ##* POST-UNINSTALLATION
        ##*===============================================
        [String]$installPhase = 'Post-Uninstallation'
		
        ## <Perform Post-Uninstallation tasks here>
		
		
    }
    ElseIf ($deploymentType -ieq 'Repair') {
        ##*===============================================
        ##* PRE-REPAIR
        ##*===============================================
        [String]$installPhase = 'Pre-Repair'
		
        ## <Perform Pre-Repair tasks here>
		
        ##*===============================================
        ##* REPAIR
        ##*===============================================
        [String]$installPhase = 'Repair'
		
        ## <Perform Repair tasks here>
		Write-Log -Message "Mode $Mode" -Source 'Mode' -LogType 'CMTrace'
		IF ($wingetmanifest -or $id -or $name -or $moniker -or $productcode -or $importfile){
			If ($ForceRepair) {
				Write-Log -Message "Start-WinGetPackageFM -UserMode $($Mode) -Action uninstall $parWinGetText" -Source 'Start-WinGetPackageFM' -LogType 'CMTrace'
				Start-WinGetPackageFM -UserMode $Mode -Action 'uninstall' -SkipUnsupported @parWinGet
				Write-Log -Message "Start-WinGetPackageFM -UserMode $($Mode) -Action install $parWinGetText" -Source 'Start-WinGetPackageFM' -LogType 'CMTrace'
				Start-WinGetPackageFM -UserMode $Mode -Action 'install' @parWinGet
			}Else{
				Write-Log -Message "Start-WinGetPackageFM -UserMode $($Mode) -Action Repair $parWinGetText" -Source 'Start-WinGetPackageFM' -LogType 'CMTrace'
				Start-WinGetPackageFM -UserMode $Mode -Action 'Repair' @parWinGet
			}

		}Else{
			Write-Log -Message "No package specified. Use -id, -name, -moniker, -wingetmanifest, -productcode or -importfile" -Severity 3 -Source 'REPAIR' -LogType 'CMTrace'
			Exit-Script -ExitCode 69001
		}
		
        ##*===============================================
        ##* POST-REPAIR
        ##*===============================================
        [String]$installPhase = 'Post-Repair'
		
        ## <Perform Post-Repair tasks here>
		
		
    }
    ##*===============================================
    ##* END SCRIPT BODY
    ##*===============================================

    ## Call the Exit-Script function to perform final cleanup operations
    Exit-Script -ExitCode $mainExitCode
}
Catch {
    [Int32]$mainExitCode = 60001
    [String]$mainErrorMessage = "$(Resolve-Error)"
    Write-Log -Message $mainErrorMessage -Severity 3 -Source $deployAppScriptFriendlyName
    Show-DialogBox -Text $mainErrorMessage -Icon 'Stop'
    Exit-Script -ExitCode $mainExitCode
}
