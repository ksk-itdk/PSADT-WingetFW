<#
.SYNOPSIS
    PSAppDeployToolkit.Extensions - WingetFW functions for PSAppDeployToolkit 4.1.

.DESCRIPTION
    Extension module for WingetFW, imported by Invoke-AppDeployToolkit.ps1. It contains the functions
    that install winget and run winget install, uninstall, upgrade, repair and import:
      Install-WinGetFM, Get-WinGetVersionFM, Start-WinGetPackageFM, Resolve-WingetPath

    Settings are read with Get-WingetFWSetting (WingetFW.Core, nested module) in this order: policy
    (HKLM\SOFTWARE\Policies\WingetFW), command line, mod file, local key (HKLM\SOFTWARE\WingetFW),
    Config\WingetFW.psd1 in this folder, built-in default.

.NOTES
    Maintained by: KSKITDK
    Version      : 5.0.0

    Release notes
    5.0.0  - First version as a PSAppDeployToolkit 4.1 extension module (was AppDeployToolkitExtensions.ps1
             in WingetFW 4.0.8). The WingetFW logic is unchanged.
           - Settings moved from AppDeployToolkitExtensionsConfig.xml to Config\WingetFW.psd1.
           - Settings from policy and the local key through WingetFW.Core: DefaultSilent, DefaultSource,
             AllowedSources, Sources (REST sources added in Admin mode), Proxy, ProxyBypass, TlsCheck,
             VCRedistCheck. Config keys renamed to TlsCheck and VCRedistCheck.
           - Mods: Invoke-WinGetActionFM runs the global and app mod sections around winget (WingetFW.Core
             Import-WingetFWMod); Start-WinGetPackageFM takes $Settings from the app mod (-ModSettings) and
             can return the result (-PassThru). A Pre section that returns $false gives exit code 69002.

.LINK
    https://github.com/ksk-itdk/PSADT-WingetFW
#>

##*===============================================
##* MARK: MODULE GLOBAL SETUP
##*===============================================

# Set strict error handling across entire module.
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 1

# WingetFW settings
$Script:WingetFWConfig = @{}
$wingetFWConfigFile = Join-Path -Path $PSScriptRoot -ChildPath 'Config\WingetFW.psd1'
if (Test-Path -LiteralPath $wingetFWConfigFile -PathType Leaf)
{
    $Script:WingetFWConfig = Import-PowerShellDataFile -LiteralPath $wingetFWConfigFile
}


##*===============================================
##* MARK: FUNCTION LISTINGS
##*===============================================

$VerbosePreference = "SilentlyContinue"
#region Function Install-WinGetFM
Function Install-WinGetFM {
    <#
.SYNOPSIS

    Install WinGet and checks if its running as user or admin

.PARAMETER UserMode

    Specifies if the script is running in user or admin mode. Allowed options: User, Admin
	
	User - will only check if the minimum version is install.
	Admin - will install the newest version if the minimum version is not detected.

.PARAMETER InstallMethod
	
	Specifies if WinGet will be installed online or a local source.
	
    Online - will install winget from GitHub.
	#####PLANED#####Local - will install from a local source.

.PARAMETER MinimumVersion

    Specifies which minimum version to check for.

    Permission DeleteSubdirectoriesAndFiles does not apply to files.

.INPUTS

None

You cannot pipe objects to this function.

.OUTPUTS

None

This function does not return any objects.

.EXAMPLE

    Will install WinGet if the version is lower and in admin mode.

    PS C:\>Install-WinGetFM -UserMode 'Admin' -InstallMethod 'Online' -MinimumVersion '2023.1005.18.0'

.EXAMPLE

    #######NOT WORKING#######
    Will install WinGet if the version is lower and in admin mode

    PS C:\>Install-WinGetFM -UserMode 'Admin' -InstallMethod 'Local' -MinimumVersion '2023.1005.18.0'

.EXAMPLE

    Will check if the version is a minimum but cannot install as it is in user mode

    PS C:\>Install-WinGetFM -UserMode 'User' -MinimumVersion '1.22.10582.0'

.NOTES

.LINK

    https://github.com/ksk-itdk/PSADT-WingetFW
#>

    [CmdletBinding()]
    Param (
		[Parameter( Mandatory = $false, Position = 0, HelpMessage = 'Specifies if the script is running in user or admin mode. Allowed options: User, Admin',ParameterSetName = 'AdminMode')]
		[ValidateSet('Admin', 'User')]
        [String]$UserMode = 'Admin',
		
		[Parameter( Mandatory = $true, Position = 0, HelpMessage = 'Specifies which minimum version to check for.',ParameterSetName = 'AdminMode')]
        [String]$MinimumVersion,
		
		[Parameter( Mandatory = $false, Position = 8, HelpMessage = 'Specifies if WinGet will be installed online or a local source.',ParameterSetName = 'AdminMode')]
		[ValidateSet('Online', 'Local', 'Wingetmodule')]
        [String]$InstallMethod
    )

    Begin {
        # Initialize function.
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    Process {
		
		Write-ADTLogEntry -Message "UserMode $UserMode" -Source 'Install-WinGetFM'
		$AppInstaller = Get-WinGetVersionFM -UserMode $UserMode
		If($UserMode -eq "Admin"){
			
			$proxySetting = Get-WingetFWSetting -Name 'Proxy' -Config $Script:WingetFWConfig
			If ($proxySetting.Value) {
				# WebProxy bypass entries are regular expressions matched against scheme://host[:port]
				$bypassSetting = Get-WingetFWSetting -Name 'ProxyBypass' -Config $Script:WingetFWConfig
				$bypassList = @(([string]$bypassSetting.Value) -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object { '://' + [regex]::Escape($_).Replace('\*', '[^/]*') + '(:\d+)?$' })
				[System.Net.WebRequest]::DefaultWebProxy = New-Object -TypeName System.Net.WebProxy -ArgumentList ([string]$proxySetting.Value), $true, ([string[]]$bypassList)
				Write-ADTLogEntry -Message "WingetFW downloads use proxy [$($proxySetting.Value)], bypass [$($bypassSetting.Value)]" -Source 'Install-WinGetFM'
			}
			
			$tlsCheck = Get-WingetFWSetting -Name 'TlsCheck' -Config $Script:WingetFWConfig -Default $true -AsBoolean
			If ($tlsCheck.Value) {
				$TlsProtocol = [Net.ServicePointManager]::SecurityProtocol
				Write-ADTLogEntry -Message "SecurityProtocol is [$TlsProtocol]" -Source 'Install-WinGetFM'
				If ([int]$TlsProtocol -eq 0) {
					# SystemDefault (0): Windows decides; TLS 1.2 is on unless SCHANNEL registry overrides it
					$Tls12Client = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client' -ErrorAction SilentlyContinue
					If ($Tls12Client.Enabled -eq 0) {
						Write-ADTLogEntry -Message "TLS 1.2 is disabled in SCHANNEL (Enabled=0), downloads will likely fail" -Source 'Install-WinGetFM' -Severity 2
					}ElseIf ($Tls12Client.DisabledByDefault -eq 1) {
						[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
						Write-ADTLogEntry -Message "TLS 1.2 is DisabledByDefault in SCHANNEL, SecurityProtocol set to [$([Net.ServicePointManager]::SecurityProtocol)]" -Source 'Install-WinGetFM'
					}
				}ElseIf (-not ($TlsProtocol -band [Net.SecurityProtocolType]::Tls12)) {
					[Net.ServicePointManager]::SecurityProtocol = $TlsProtocol -bor [Net.SecurityProtocolType]::Tls12
					Write-ADTLogEntry -Message "TLS 1.2 missing, SecurityProtocol set to [$([Net.ServicePointManager]::SecurityProtocol)]" -Source 'Install-WinGetFM'
				}
			}Else{
				Write-ADTLogEntry -Message "TLS check disabled (TlsCheck from [$($tlsCheck.Source)])" -Source 'Install-WinGetFM'
			}
			
			$vcRedistCheck = Get-WingetFWSetting -Name 'VCRedistCheck' -Config $Script:WingetFWConfig -Default $true -AsBoolean
			If ($vcRedistCheck.Value) {
				# VC++ 2015-2022 runtime matching the OS (x64/x86); winget.exe run as SYSTEM can't use the MSIX VCLibs and crashes with 0xC000007B without it
				$VCArch = If ([Environment]::Is64BitOperatingSystem) { 'x64' } Else { 'x86' }
				# Registry64 gives the native view on 64-bit Windows (also from a 32-bit process) and the normal view on 32-bit Windows
				$RegLM = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
				$VCKey = "SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\$VCArch","SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\$VCArch" | ForEach-Object { $RegLM.OpenSubKey($_) } | Where-Object { $_ -and $_.GetValue('Installed') -eq 1 } | Select-Object -First 1
				If ($VCKey) {
					Write-ADTLogEntry -Message "VC++ $VCArch runtime already installed, version [$($VCKey.GetValue('Version'))]" -Source 'Install-WinGetFM'
				}Else{
					if (!(Test-Path -Path C:\ProgramData\WinGetPackages)) {
						New-Item -Path C:\ProgramData\WinGetPackages -Force -ItemType Directory
					}
					Write-ADTLogEntry -Message "Downloading vc_redist.$VCArch.exe from https://aka.ms/vs/17/release/vc_redist.$VCArch.exe" -Source 'Install-WinGetFM'
					Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.$VCArch.exe" -OutFile "C:\ProgramData\WinGetPackages\vc_redist.$VCArch.exe" -UseBasicParsing
					$result = Start-ADTProcess -FilePath "C:\ProgramData\WinGetPackages\vc_redist.$VCArch.exe" -ArgumentList '/install /quiet /norestart' -CreateNoWindow -IgnoreExitCodes '1638' -PassThru -ErrorAction SilentlyContinue
					# PSADT ignores -ExitOnProcessFailure for PSAppDeployToolkit.* modules, so the exit code is passed on here
					If ($result.ExitCode -in @(1641, 3010)) {
						(Get-ADTSession).SetExitCode($result.ExitCode)
					}
					ElseIf ($result.ExitCode -notin @(0, 1638)) {
						Close-ADTSession -ExitCode $result.ExitCode
					}
				}
				$RegLM.Close()
			}Else{
				Write-ADTLogEntry -Message "VC++ runtime check disabled (VCRedistCheck from [$($vcRedistCheck.Source)])" -Source 'Install-WinGetFM'
			}
			
			If([version]$AppInstaller.WingetVersion -lt [version]$MinimumVersion) {
				
				Write-ADTLogEntry -Message "Winget is not installed, trying to install latest version from Github" -Source 'Install-WinGetFM'
				
				Try {
					
					Write-ADTLogEntry -Message "Creating Winget Packages Folder" -Source 'Install-WinGetFM'
					
					if (!(Test-Path -Path C:\ProgramData\WinGetPackages)) {
						New-Item -Path C:\ProgramData\WinGetPackages -Force -ItemType Directory
					}
					Switch ($InstallMethod) {
						'Online' {
							#Set-Location C:\ProgramData\WinGetPackages
							
							#Downloading Packagefiles
							Write-ADTLogEntry -Message "Setting ProgressPreference to SilentlyContinue" -Source 'Install-WinGetFM'
							$ProgressPreference = 'SilentlyContinue'
							#Download Winget.Source
							Write-ADTLogEntry -Message "Downloading winget-source.msix from https://cdn.winget.microsoft.com/cache/source.msix" -Source 'Install-WinGetFM'
							Invoke-WebRequest -Uri "https://cdn.winget.microsoft.com/cache/source.msix" -OutFile "C:\ProgramData\WinGetPackages\winget-source.msix" -UseBasicParsing
							#Microsoft.UI.Xaml - newest
							Write-ADTLogEntry -Message "Downloading microsoft.ui.xaml.newest.zip from https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/" -Source 'Install-WinGetFM'
							Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/" -OutFile "C:\ProgramData\WinGetPackages\microsoft.ui.xaml.newest.zip" -UseBasicParsing
							Write-ADTLogEntry -Message "Exstract C:\ProgramData\WinGetPackages\microsoft.ui.xaml.newest.zip" -Source 'Install-WinGetFM'
							Expand-Archive -LiteralPath "C:\ProgramData\WinGetPackages\microsoft.ui.xaml.newest.zip" -DestinationPath "C:\ProgramData\WinGetPackages\microsoft.ui.xaml.newest" -Force
							#Microsoft.VCLibs.140.00.UWPDesktop
							Write-ADTLogEntry -Message "Downloading Microsoft.VCLibs.x64.14.00.Desktop.appx from https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -Source 'Install-WinGetFM'
							Invoke-WebRequest -Uri "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -OutFile "C:\ProgramData\WinGetPackages\Microsoft.VCLibs.x64.14.00.Desktop.appx" -UseBasicParsing
							#Winget
							Write-ADTLogEntry -Message "Downloading Winget.msixbundle from https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -Source 'Install-WinGetFM'
							Invoke-WebRequest -Uri "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -OutFile "C:\ProgramData\WinGetPackages\Winget.msixbundle" -UseBasicParsing
							Write-ADTLogEntry -Message 'Finding the MicrosoftUIXaml Version and shave the it to $MicrosoftUIXamlVersion' -Source 'Install-WinGetFM'
							$MicrosoftUIXamlVersion = Get-ChildItem C:\ProgramData\WinGetPackages\microsoft.ui.xaml.newest\tools\AppX\x64\Release -recurse | where {$_.name -like "Microsoft.UI.Xaml.*"} | select name
							#Installing dependencies + Winget
							Write-ADTLogEntry -Message "Installing winget and Dependency Package" -Source 'Install-WinGetFM'
							Add-ProvisionedAppxPackage -online -PackagePath:C:\ProgramData\WinGetPackages\Winget.msixbundle -DependencyPackagePath C:\ProgramData\WinGetPackages\Microsoft.VCLibs.x64.14.00.Desktop.appx,C:\ProgramData\WinGetPackages\microsoft.ui.xaml.newest\tools\AppX\x64\Release\$($MicrosoftUIXamlVersion.name) -SkipLicense
							#Installing Winget.Source
							Write-ADTLogEntry -Message "Installing winget-source" -Source 'Install-WinGetFM'
							Add-AppxProvisionedPackage -Online -PackagePath "C:\ProgramData\WinGetPackages\winget-source.msix" -SkipLicense
							
						}
						'Local' {
							Write-ADTLogEntry -Message "ERROR Local install NOT ready to use" -Source 'Install-WinGetFM'
							Throw "Failed to install Winget"
							Break
						}
						'Wingetmodule' {
							Write-ADTLogEntry -Message "ERROR Local Wingetmodule NOT ready to use" -Source 'Install-WinGetFM'
							Throw "Failed to install Winget"
							Break
						}
					}
					
					Write-ADTLogEntry -Message "Starting sleep for Winget to initiate" -Source 'Install-WinGetFM'
					Start-Sleep 2
				}
				Catch {
					Throw "Failed to install Winget"
					Write-ADTLogEntry -Message "$Error[0].Exception" -Source 'Install-WinGetFM'
					Break
				}
			
			}Else{
				Write-ADTLogEntry -Message "Winget already installed, moving on" -Source 'Install-WinGetFM'
			}
			Try {
				If(!(Get-AppxPackage -AllUsers Microsoft.Winget.Source*)) {
					
					if (!(Test-Path -Path C:\ProgramData\WinGetPackages)) {
						Write-ADTLogEntry -Message "Creating Winget Packages Folder" -Source 'Install-WinGetFM'
						New-Item -Path C:\ProgramData\WinGetPackages -Force -ItemType Directory
					}
					#Download Winget.Source
					Write-ADTLogEntry -Message "Downloading winget-source.msix from https://cdn.winget.microsoft.com/cache/source.msix" -Source 'Install-WinGetFM'
					Invoke-WebRequest -Uri "https://cdn.winget.microsoft.com/cache/source.msix" -OutFile "C:\ProgramData\WinGetPackages\winget-source.msix" -UseBasicParsing
					#Installing Winget.Source
					Write-ADTLogEntry -Message "Installing winget-source" -Source 'Install-WinGetFM'
					Add-AppxProvisionedPackage -Online -PackagePath "C:\ProgramData\WinGetPackages\winget-source.msix" -SkipLicense
				}else{
					Write-ADTLogEntry -Message "winget-source already installed, moving on" -Source 'Install-WinGetFM'
				}
			}
			Catch {
				Throw "Failed to install winget-source"
				Write-ADTLogEntry -Message "$Error[0].Exception" -Source 'Install-WinGetFM'
				Break
			}
			Add-WingetFWSourceFM
        }
		If($UserMode -eq "User"){
			Write-ADTLogEntry -Message "UserMode $UserMode" -Source 'Install-WinGetFM'
			If([version]$AppInstaller.WingetVersion -lt [version]$MinimumVersion) {
				Write-ADTLogEntry -Message "Winget is not installed" -Source 'Install-WinGetFM'
			}Else{
				Write-ADTLogEntry -Message "Winget already installed, moving on" -Source 'Install-WinGetFM'
			}
        }
	}
		
    End {
        Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}
#endregion

#region Function Get-WinGetVersionFM
Function Get-WinGetVersionFM {
    <#
.SYNOPSIS

    Check for WinGet and version

.PARAMETER UserMode

    Specifies if the check is running in user or admin mode. Allowed options: User, Admin
	
	User - will check the version with Get-AppxPackage.
	Admin - will check the version with Get-AppxProvisionedPackage.

.INPUTS

None

You cannot pipe objects to this function.

.OUTPUTS

None

This function return winget version and a true/false.

.EXAMPLE

    Will check the WinGet version for admin/system, do not work with a user account

    PS C:\>Get-WinGetVersionFM -UserMode 'Admin'

.EXAMPLE

    Will check the WinGet version for user, do not work with system account

    PS C:\>Get-WinGetVersionFM -UserMode 'User'

.NOTES

.LINK

    https://github.com/ksk-itdk/PSADT-WingetFW
#>

    [CmdletBinding()]
    Param (
		[Parameter( Mandatory = $false, Position = 0, HelpMessage = 'Specifies if the script is running in user or admin mode. Allowed options: User, Admin',ParameterSetName = 'AdminMode')]
		[ValidateSet('Admin', 'User')]
        [String]$UserMode = 'Admin'	
    )

    Begin {
        # Initialize function.
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    Process {
		Write-ADTLogEntry -Message "Starting check of WinGet" -Source 'Get-WinGetVersionFM'
		If($UserMode -eq "Admin"){
			$AppInstaller = Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq Microsoft.DesktopAppInstaller
			Write-ADTLogEntry -Message "Checking install version $(($AppInstaller).Version)" -Source 'Get-WinGetVersionFM-Admin'
		}
		If($UserMode -eq "User"){
			$AppInstaller = Get-AppxPackage | Where-Object Name -eq Microsoft.DesktopAppInstaller
			Write-ADTLogEntry -Message "Checking install version $(($AppInstaller).Version)" -Source 'Get-WinGetVersionFM-User'
		}
		$myObject = @()
		If($AppInstaller -eq $null){
			$myObject = [PSCustomObject]@{
				"WingetVersion" = '0.0.0.0'
				"WingetBoolean" = $false
			}
		}else{
			$myObject = [PSCustomObject]@{
				"WingetVersion" = $(($AppInstaller).Version)
				"WingetBoolean" = $true
			}
		}
		
		return $myObject
	}
		
    End {
        Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}
#endregion

#region Function Start-WinGetPackageFM
Function Start-WinGetPackageFM {
    <#
.SYNOPSIS

    Install WinGet a Package and checks if its running as user or admin

.PARAMETER UserMode

    Specifies if the script is running in user or admin mode. Allowed options: User, Admin
	
	User - will user the WinGet.exe from appdata to install the package.
	Admin - will user the WinGet.exe from ProgramFiles to install the Package.
	
.PARAMETER Action

    Specifies if you need to install, uninstall, upgrade, import or repair.
	
.PARAMETER wingetmanifest
	
	Must be followed by the path to the manifest (YAML) file. You can use the manifest to run the install experience from a local YAML file.

.PARAMETER id

    Limits the install to the ID of the application.

.PARAMETER name

    Limits the search to the name of the application.

.PARAMETER moniker

    Limits the search to the moniker listed for the application.

.PARAMETER version

    Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.

.PARAMETER source

    Restricts the search to the source name provided. Must be followed by the source name.

.PARAMETER scope

    Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.

.PARAMETER architecture

    Select the architecture to install.

.PARAMETER installertypes

    Select the installer type to install. See supported installer types for WinGet client.

.PARAMETER exact

    Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.

.PARAMETER interactive

    Runs the installer in interactive mode. The default experience shows installer progress.

.PARAMETER silent

    Runs the installer in silent mode. This suppresses all UI. The default experience shows installer progress.

.PARAMETER locale

    Specifies which locale to use (BCP47 format).

.PARAMETER log

    Directs the logging to a log file. You must provide a path to a file that you have the write rights to.

.PARAMETER custom

    Arguments to be passed on to the installer in addition to the defaults.

.PARAMETER override

    A string that will be passed directly to the installer.

.PARAMETER location

    Location to install to (if supported).

.PARAMETER ignoresecurityhash

    Ignore the installer hash check failure. Not recommended.

.PARAMETER allowreboot

    Allows a reboot if applicable.

.PARAMETER skipdependencies

    Skips processing package dependencies and Windows features.

.PARAMETER ignorelocalarchivemalwarescan

    Ignore the malware scan performed as part of installing an archive type package from local manifest.

.PARAMETER dependencysource

    Find package dependencies using the specified source.

.PARAMETER acceptpackageagreements

    Used to accept the license agreement, and avoid the prompt.

.PARAMETER noupgrade

    Skips upgrade if an installed version already exists.

.PARAMETER header

    Optional Windows-Package-Manager REST source HTTP header.

.PARAMETER authenticationmode

    Specify authentication window preference (silent, silentPreferred or interactive).

.PARAMETER authenticationaccount

    Specify the account to be used for authentication.

.PARAMETER acceptsourceagreements

    Used to accept the source license agreement, and avoid the prompt.

.PARAMETER rename

    The value to rename the executable file (portable).

.PARAMETER uninstallprevious

    Uninstall the previous version of the package during upgrade.

.PARAMETER force

    Direct run the command and continue with non security related issues.

.PARAMETER enableverbose

    Used to override the logging setting and create a verbose log.

.PARAMETER ignorewarnings

    Suppresses warning outputs.

.PARAMETER disableinteractivity

    Disable interactive prompts.

.PARAMETER proxy

    Set a proxy to use for this execution.

.PARAMETER noproxy

    Disable the use of proxy for this execution.

.PARAMETER importfile

    JSON file describing the packages to install (import).

.PARAMETER ignoreunavailable

    Suppresses errors if the app requested is unavailable (import).

.PARAMETER ignoreversions

    Ignores versions specified in the JSON file and installs the latest available version (import).

.PARAMETER productcode

    Filters using the product code (uninstall, repair).

.PARAMETER allversions

    Uninstall all versions (uninstall).

.PARAMETER purge

    Deletes all files and directories in the package directory (portable) (uninstall, upgrade).

.PARAMETER preserve

    Retains all files and directories created by the package (portable) (uninstall).

.PARAMETER includeunknown

    Upgrade packages even if their current version cannot be determined (upgrade).

.PARAMETER includepinned

    Upgrade packages even if they have a non-blocking pin (upgrade).

.PARAMETER SkipUnsupported

    Skip and log options the action does not support instead of throwing. Used by -ForceRepair for the uninstall step.

.INPUTS

None

You cannot pipe objects to this function.

.OUTPUTS

None

This function does not return any objects.

.EXAMPLE

    Will Install 7-zip

    PS C:\>Start-WinGetPackageFM -UserMode 'Admin' -Action 'Install' -wingetmanifest 'C:\temp\7zip.7zip.yml' -scope 'Machine'

.EXAMPLE

    Will Install 7-zip

    PS C:\>Start-WinGetPackageFM -UserMode 'Admin -Action 'Install' -id '7zip.7zip' -scope 'Machine'

.EXAMPLE

    Will Install 7-zip

    PS C:\>Start-WinGetPackageFM -UserMode 'User' -Action 'Install' -name '7-Zip' -exact -scope 'User'

.NOTES

.LINK

    https://github.com/ksk-itdk/PSADT-WingetFW
#>

    [CmdletBinding()]
    Param (
		[Parameter( Mandatory = $false, HelpMessage = 'Specifies if the script is running in user or admin mode. Allowed options: User, Admin')]
        [ValidateSet('Admin', 'User')]
        [String]$UserMode,
		
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
		
		[Parameter( Mandatory = $false, HelpMessage = 'Skip and log options the action does not support instead of throwing.')]
        [Switch]$SkipUnsupported,
		
		[Parameter( Mandatory = $false, HelpMessage = 'Settings for this action from the app mod file ($Settings.<Action>). The command line beats them.')]
        [Hashtable]$ModSettings = @{},
		
		[Parameter( Mandatory = $false, HelpMessage = 'Return ExitCode and Success instead of ending the deployment when winget fails.')]
        [Switch]$PassThru
		
    )

    Begin {
        # Initialize function.
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    Process {
		Write-Verbose "PSBoundParameters: $($PSBoundParameters.Keys)"
		
		# Options each winget command supports: learn.microsoft.com/windows/package-manager/winget/<command>
		$wingetQuery = @('wingetmanifest', 'id', 'name', 'moniker', 'version', 'source', 'exact')
		$wingetGlobal = @('enableverbose', 'ignorewarnings', 'disableinteractivity', 'proxy', 'noproxy')
		$supportedOptions = @{
			'Install'   = $wingetQuery + $wingetGlobal + @('scope', 'architecture', 'installertype', 'interactive', 'silent', 'locale', 'log', 'custom', 'override', 'location', 'ignoresecurityhash', 'allowreboot', 'skipdependencies', 'ignorelocalarchivemalwarescan', 'dependencysource', 'noupgrade', 'header', 'authenticationmode', 'authenticationaccount', 'rename', 'uninstallprevious', 'force')
			'Uninstall' = $wingetQuery + $wingetGlobal + @('productcode', 'allversions', 'scope', 'interactive', 'silent', 'force', 'purge', 'preserve', 'log', 'header', 'authenticationmode', 'authenticationaccount')
			'Upgrade'   = $wingetQuery + $wingetGlobal + @('interactive', 'silent', 'purge', 'log', 'custom', 'override', 'location', 'scope', 'architecture', 'installertype', 'locale', 'ignoresecurityhash', 'allowreboot', 'skipdependencies', 'ignorelocalarchivemalwarescan', 'header', 'authenticationmode', 'authenticationaccount', 'includeunknown', 'includepinned', 'uninstallprevious', 'force')
			'Repair'    = $wingetQuery + $wingetGlobal + @('productcode', 'architecture', 'scope', 'interactive', 'silent', 'log', 'ignorelocalarchivemalwarescan', 'locale', 'header', 'authenticationmode', 'authenticationaccount', 'force', 'ignoresecurityhash')
			'Import'    = $wingetGlobal + @('importfile', 'ignoreunavailable', 'ignoreversions', 'noupgrade')
		}
		# Agreements are handled per action further down
		$notChecked = @('UserMode', 'Action', 'acceptpackageagreements', 'acceptsourceagreements', 'SkipUnsupported', 'ModSettings', 'PassThru') + [System.Management.Automation.PSCmdlet]::CommonParameters
		
		# winget options from the app mod file, only when the command line does not set them
		$modOptions = @{ Override = 'override'; Custom = 'custom'; Scope = 'scope'; Locale = 'locale'; Architecture = 'architecture'; Source = 'source'; SkipDependencies = 'skipdependencies' }
		ForEach ($key in @($ModSettings.Keys)) {
			If (-not $modOptions.ContainsKey($key)) {
				If ($key -notin @('DefaultSilent', 'DefaultSource', 'Proxy')) {
					Write-ADTLogEntry -Message "Ignoring [$key] in the mod file `$Settings, it is not a WingetFW setting" -Source 'Start-WinGetPackageFM' -Severity 2
				}
				Continue
			}
			$option = $modOptions[$key]
			$current = $PSBoundParameters[$option]
			$isSet = If ($current -is [System.Management.Automation.SwitchParameter]) { $current.IsPresent } Else { -not [string]::IsNullOrEmpty($current) }
			If ($isSet) {
				Write-ADTLogEntry -Message "-$option on the command line beats $key in the mod file" -Source 'Start-WinGetPackageFM'
				Continue
			}
			$value = If ($option -eq 'skipdependencies') { [Switch][Bool]$ModSettings[$key] } Else { [String]$ModSettings[$key] }
			Set-Variable -Name $option -Value $value
			$PSBoundParameters[$option] = $value
			Write-ADTLogEntry -Message "Using -$option '$value' from the mod file" -Source 'Start-WinGetPackageFM'
		}
		
		$usedOptions = @()
		ForEach ($key in @($PSBoundParameters.Keys)) {
			If ($key -in $notChecked) { Continue }
			$value = $PSBoundParameters[$key]
			# Deploy-Application passes unused switches as $false
			$isUsed = If ($value -is [System.Management.Automation.SwitchParameter]) { $value.IsPresent } Else { -not [string]::IsNullOrEmpty($value) }
			If (-not $isUsed) { Continue }
			If ($key -notin $supportedOptions[$Action]) {
				If ($SkipUnsupported) {
					Write-ADTLogEntry -Message "Skipping -$key, it is not an option with winget $Action" -Source 'Start-WinGetPackageFM' -Severity 2
					Set-Variable -Name $key -Value $null
					Continue
				}
				Throw "-$key is not an option with winget $Action. Allowed: -$($supportedOptions[$Action] -join ', -')"
			}
			$usedOptions += $key
		}
		ForEach ($group in @(@('wingetmanifest', 'id', 'name', 'moniker'), @('interactive', 'silent', 'override'), @('proxy', 'noproxy'), @('purge', 'preserve'))) {
			$conflict = @($usedOptions | Where-Object { $_ -in $group })
			If ($conflict.Count -gt 1) {
				Throw "-$($conflict -join ' and -') cannot be used together. Use only one of -$($group -join ', -')."
			}
		}
		If ('header' -in $usedOptions -and 'source' -notin $usedOptions) {
			Throw "-header requires -source. winget rejects --header without --source."
		}
		
		# Settings: policy, command line, local key, config file, default (Get-WingetFWSetting in WingetFW.Core)
		$proxySetting = Get-WingetFWSetting -Name 'Proxy' -CommandLine $(If ($proxy) { @{ Proxy = $proxy } } Else { @{} }) -ModSettings $ModSettings -Config $Script:WingetFWConfig
		If ($proxySetting.Source -eq 'Policy' -and $noproxy) {
			Write-ADTLogEntry -Message "Ignoring -noproxy, Proxy is set by policy" -Source 'Start-WinGetPackageFM' -Severity 2
			$noproxy = [switch]$false
		}
		If ($proxySetting.Value -and -not $noproxy) { $proxy = [string]$proxySetting.Value }
		
		If ('silent' -in $supportedOptions[$Action] -and -not ($silent -or $interactive -or $override)) {
			$silentSetting = Get-WingetFWSetting -Name 'DefaultSilent' -ModSettings $ModSettings -Config $Script:WingetFWConfig -Default $true -AsBoolean
			If ($silentSetting.Value) {
				$silent = [switch]$true
				Write-ADTLogEntry -Message "Adding -silent (DefaultSilent from [$($silentSetting.Source)])" -Source 'Start-WinGetPackageFM'
			}
		}
		
		# Uninstall and repair work on installed packages, so the default source only applies to install and upgrade
		If (-not $source -and $Action -in @('Install', 'Upgrade') -and ($id -or $name -or $moniker)) {
			$sourceSetting = Get-WingetFWSetting -Name 'DefaultSource' -ModSettings $ModSettings -Config $Script:WingetFWConfig
			If ($sourceSetting.Value) {
				$source = [string]$sourceSetting.Value
				Write-ADTLogEntry -Message "Using source [$source] (DefaultSource from [$($sourceSetting.Source)])" -Source 'Start-WinGetPackageFM'
			}
		}
		
		$allowedSetting = Get-WingetFWSetting -Name 'AllowedSources' -Config $Script:WingetFWConfig
		If ($allowedSetting.Value) {
			$allowedSources = @($allowedSetting.Value)
			ForEach ($usedSource in @($source, $dependencysource) | Where-Object { $_ }) {
				If ($usedSource -notin $allowedSources) {
					Throw "Source [$usedSource] is not allowed. Allowed sources: $($allowedSources -join ', ') (AllowedSources from [$($allowedSetting.Source)])"
				}
			}
		}
		
		$argsWinGet = $null
		Switch ($scope) {
            'User' {
                $argsWinGet += " --scope user"
				Write-Verbose "Adding scope to argsWinGet: $($argsWinGet)"
            }
            'Machine' {
                $argsWinGet += " --scope machine"
				Write-Verbose "Adding scope to argsWinGet: $($argsWinGet)"
            }
        }
		
		Switch ($architecture) {
            'Default' {
                
            }
            'X86' {
                $argsWinGet += " --architecture x86"
				Write-Verbose "Adding architecture to argsWinGet: $($argsWinGet)"
            }
            'Arm' {
                $argsWinGet += " --architecture arm"
				Write-Verbose "Adding architecture to argsWinGet: $($argsWinGet)"
            }
            'X64' {
                $argsWinGet += " --architecture x64"
				Write-Verbose "Adding architecture to argsWinGet: $($argsWinGet)"
            }
            'Arm64' {
                $argsWinGet += " --architecture arm64"
				Write-Verbose "Adding architecture to argsWinGet: $($argsWinGet)"
            }
        }
		
		Switch ($installertype) {
            'Default' {
                
            }
            'Inno' {
                $argsWinGet += " --installer-type inno"
				Write-Verbose "Adding installertype to argsWinGet: $($argsWinGet)"
            }
            'Wix' {
                $argsWinGet += " --installer-type wix"
				Write-Verbose "Adding installertype to argsWinGet: $($argsWinGet)"
            }
            'Msi' {
                $argsWinGet += " --installer-type msi"
				Write-Verbose "Adding installertype to argsWinGet: $($argsWinGet)"
            }
            'Nullsoft' {
                $argsWinGet += " --installer-type nullsoft"
				Write-Verbose "Adding installertype to argsWinGet: $($argsWinGet)"
            }
			'Zip' {
                $argsWinGet += " --installer-type zip"
				Write-Verbose "Adding installertype to argsWinGet: $($argsWinGet)"
            }
            'Msix' {
                $argsWinGet += " --installer-type msix"
				Write-Verbose "Adding installertype to argsWinGet: $($argsWinGet)"
            }
            'Exe' {
                $argsWinGet += " --installer-type exe"
				Write-Verbose "Adding installertype to argsWinGet: $($argsWinGet)"
            }
            'Burn' {
                $argsWinGet += " --installer-type burn"
				Write-Verbose "Adding installertype to argsWinGet: $($argsWinGet)"
            }
            'MSStore' {
                $argsWinGet += " --installer-type msstore"
				Write-Verbose "Adding installertype to argsWinGet: $($argsWinGet)"
            }
			'Portable' {
                $argsWinGet += " --installer-type portable"
				Write-Verbose "Adding installertype to argsWinGet: $($argsWinGet)"
            }
        }
		
		Switch ($authenticationmode) {
            'silent' {
                $argsWinGet += " --authentication-mode silent"
				Write-Verbose "Adding authenticationmode to argsWinGet: $($argsWinGet)"
            }
            'silentPreferred' {
                $argsWinGet += " --authentication-mode silentPreferred"
				Write-Verbose "Adding authenticationmode to argsWinGet: $($argsWinGet)"
            }
            'interactive' {
                $argsWinGet += " --authentication-mode interactive"
				Write-Verbose "Adding authenticationmode to argsWinGet: $($argsWinGet)"
            }
        }
		
		If ($wingetmanifest) {
			Write-Verbose "IF wingetmanifest: $($wingetmanifest)"
            $argsWinGet += " --manifest $([char]34)$wingetmanifest$([char]34)"
			Write-Verbose "Adding wingetmanifest to argsWinGet: $($argsWinGet)"
        }
		If ($id) {
			Write-Verbose "IF id: $($id)"
            $argsWinGet += " --id $id"
			Write-Verbose "Adding id to argsWinGet: $($argsWinGet)"
        }
        If ($name) {
			$name=$name.Replace("$([char]39)","$([char]34)$([char]34)")
			Write-Verbose "IF name: $($name)"
            $argsWinGet += " --name $([char]34)$name$([char]34)"
			Write-Verbose "Adding name to argsWinGet: $($argsWinGet)"
        }
        If ($moniker) {
			Write-Verbose "IF moniker: $($moniker)"
            $argsWinGet += " --moniker $moniker"
			Write-Verbose "Adding moniker to argsWinGet: $($argsWinGet)"
        }
        If ($version) {
			Write-Verbose "IF version: $($version)"
            $argsWinGet += " --version $version"
			Write-Verbose "Adding version to argsWinGet: $($argsWinGet)"
        }
        If ($source) {
			Write-Verbose "IF source: $($source)"
            $argsWinGet += " --source $source"
			Write-Verbose "Adding source to argsWinGet: $($argsWinGet)"
        }
		If ($exact) {
			Write-Verbose "IF exact: $($exact)"
            $argsWinGet += " --exact"
			Write-Verbose "Adding exact to argsWinGet: $($argsWinGet)"
        }
		If ($interactive) {
			Write-Verbose "IF interactive: $($interactive)"
            $argsWinGet += " --interactive"
			Write-Verbose "Adding interactive to argsWinGet: $($argsWinGet)"
        }
        If ($silent) {
			Write-Verbose "IF silent: $($silent)"
            $argsWinGet += " --silent"
			Write-Verbose "Adding silent to argsWinGet: $($argsWinGet)"
        }
        If ($locale) {
			Write-Verbose "IF locale: $($locale)"
            $argsWinGet += " --locale $locale"
			Write-Verbose "Adding locale to argsWinGet: $($argsWinGet)"
        }
        If ($log) {
			Write-Verbose "IF log: $($log)"
            $argsWinGet += " --log $([char]34)$log$([char]34)"
			Write-Verbose "Adding log to argsWinGet: $($argsWinGet)"
        }
        If ($custom) {
			$custom=$custom.Replace("$([char]39)","$([char]34)$([char]34)")
			Write-Verbose "IF custom: $($custom)"
            $argsWinGet += " --custom $([char]34)$custom$([char]34)"
			Write-Verbose "Adding custom to argsWinGet: $($argsWinGet)"
        }
		If ($override) {
			$override=$override.Replace("$([char]39)","$([char]34)$([char]34)")
			Write-Verbose "IF override: $($override)"
			$argsWinGet += " --override $([char]34)$override$([char]34)"
			Write-Verbose "Adding override to argsWinGet: $($argsWinGet)"
        }
        If ($location) {
			Write-Verbose "IF location: $($location)"
			if(($location -notmatch [char]39)-and($location -notmatch [char]34)){
				$argsWinGet += " --location $([char]34)$location$([char]34)"
			}else{
				$argsWinGet += " --location $location"
			}
			Write-Verbose "Adding location to argsWinGet: $($argsWinGet)"
        }
        If ($ignoresecurityhash) {
			Write-Verbose "IF ignoresecurityhash: $($ignoresecurityhash)"
            $argsWinGet += " --ignore-security-hash"
			Write-Verbose "Adding ignoresecurityhash to argsWinGet: $($argsWinGet)"
        }
        If ($allowreboot) {
			Write-Verbose "IF allowreboot: $($allowreboot)"
            $argsWinGet += " --allow-reboot"
			Write-Verbose "Adding allowreboot to argsWinGet: $($argsWinGet)"
        }
		If ($skipdependencies) {
			Write-Verbose "IF skipdependencies: $($skipdependencies)"
            $argsWinGet += " --skip-dependencies"
			Write-Verbose "Adding skipdependencies to argsWinGet: $($argsWinGet)"
        }
		If ($ignorelocalarchivemalwarescan) {
			Write-Verbose "IF ignorelocalarchivemalwarescan: $($ignorelocalarchivemalwarescan)"
            $argsWinGet += " --ignore-local-archive-malware-scan"
			Write-Verbose "Adding ignorelocalarchivemalwarescan to argsWinGet: $($argsWinGet)"
        }
        If ($dependencysource) {
			Write-Verbose "IF dependencysource: $($dependencysource)"
            $argsWinGet += " --dependency-source $dependencysource"
			Write-Verbose "Adding dependencysource to argsWinGet: $($argsWinGet)"
        }
		# winget uninstall does not support --accept-package-agreements
		If (($acceptpackageagreements) -AND ($Action -NE 'Uninstall')) {
			Write-Verbose "IF acceptpackageagreements: $($acceptpackageagreements)"
			$argsWinGet += " --accept-package-agreements"
			Write-Verbose "Adding acceptpackageagreements to argsWinGet: $($argsWinGet)"
		}
        If ($noupgrade) {
			Write-Verbose "IF noupgrade: $($noupgrade)"
            $argsWinGet += " --no-upgrade"
			Write-Verbose "Adding noupgrade to argsWinGet: $($argsWinGet)"
        }
        If ($header) {
			Write-Verbose "IF header: $($header)"
            $argsWinGet += " --header $([char]34)$header$([char]34)"
			Write-Verbose "Adding header to argsWinGet: $($argsWinGet)"
        }
		If ($authenticationaccount) {
			Write-Verbose "IF authenticationaccount: $($authenticationaccount)"
			$argsWinGet += " --authentication-account $authenticationaccount"
			Write-Verbose "Adding authenticationaccount to argsWinGet: $($argsWinGet)"
        }
		If (($($PSBoundParameters.Keys) -Match 'acceptsourceagreements')-OR($Action -NE 'Uninstall')){
			Write-Verbose "PSBoundParameters -Match acceptsourceagreements)"
			If ($acceptsourceagreements) {
				Write-Verbose "IF acceptsourceagreements: $($acceptsourceagreements)"
				$argsWinGet += " --accept-source-agreements"
				Write-Verbose "Adding acceptsourceagreements to argsWinGet: $($argsWinGet)"
			}
		}
        If ($rename) {
			Write-Verbose "IF rename: $($rename)"
            $argsWinGet += " --rename $([char]34)$rename$([char]34)"
			Write-Verbose "Adding rename to argsWinGet: $($argsWinGet)"
        }
        If ($uninstallprevious) {
			Write-Verbose "IF uninstallprevious: $($uninstallprevious)"
            $argsWinGet += " --uninstall-previous"
			Write-Verbose "Adding uninstallprevious to argsWinGet: $($argsWinGet)"
        }
		If ($force) {
			Write-Verbose "IF force: $($force)"
            $argsWinGet += " --force"
			Write-Verbose "Adding force to argsWinGet: $($argsWinGet)"
        }
        If ($enableverbose) {
			Write-Verbose "IF enableverbose: $($enableverbose)"
            $argsWinGet += " --verbose"
			Write-Verbose "Adding enableverbose to argsWinGet: $($argsWinGet)"
        }
        If ($ignorewarnings) {
			Write-Verbose "IF ignorewarnings: $($ignorewarnings)"
            $argsWinGet += " --ignore-warnings"
			Write-Verbose "Adding ignorewarnings to argsWinGet: $($argsWinGet)"
        }
        If ($disableinteractivity) {
			Write-Verbose "IF disableinteractivity: $($disableinteractivity)"
            $argsWinGet += " --disable-interactivity"
			Write-Verbose "Adding disableinteractivity to argsWinGet: $($argsWinGet)"
        }
        If ($proxy) {
			Write-Verbose "IF proxy: $($proxy)"
            $argsWinGet += " --proxy $proxy"
			Write-Verbose "Adding proxy to argsWinGet: $($argsWinGet)"
        }
		If ($noproxy) {
			Write-Verbose "IF noproxy: $($noproxy)"
            $argsWinGet += " --no-proxy"
			Write-Verbose "Adding noproxy to argsWinGet: $($argsWinGet)"
        }
		If ($importfile) {
			Write-Verbose "IF importfile: $($importfile)"
			$argsWinGet += " --import-file $([char]34)$importfile$([char]34)"
			Write-Verbose "Adding importfile to argsWinGet: $($argsWinGet)"
		}
		If ($ignoreunavailable) {
			Write-Verbose "IF ignoreunavailable: $($ignoreunavailable)"
			$argsWinGet += " --ignore-unavailable"
			Write-Verbose "Adding ignoreunavailable to argsWinGet: $($argsWinGet)"
		}
		If ($ignoreversions) {
			Write-Verbose "IF ignoreversions: $($ignoreversions)"
			$argsWinGet += " --ignore-versions"
			Write-Verbose "Adding ignoreversions to argsWinGet: $($argsWinGet)"
		}
		If ($productcode) {
			Write-Verbose "IF productcode: $($productcode)"
			$argsWinGet += " --product-code $productcode"
			Write-Verbose "Adding productcode to argsWinGet: $($argsWinGet)"
		}
		If ($allversions) {
			Write-Verbose "IF allversions: $($allversions)"
			$argsWinGet += " --all-versions"
			Write-Verbose "Adding allversions to argsWinGet: $($argsWinGet)"
		}
		If ($purge) {
			Write-Verbose "IF purge: $($purge)"
			$argsWinGet += " --purge"
			Write-Verbose "Adding purge to argsWinGet: $($argsWinGet)"
		}
		If ($preserve) {
			Write-Verbose "IF preserve: $($preserve)"
			$argsWinGet += " --preserve"
			Write-Verbose "Adding preserve to argsWinGet: $($argsWinGet)"
		}
		If ($includeunknown) {
			Write-Verbose "IF includeunknown: $($includeunknown)"
			$argsWinGet += " --include-unknown"
			Write-Verbose "Adding includeunknown to argsWinGet: $($argsWinGet)"
		}
		If ($includepinned) {
			Write-Verbose "IF includepinned: $($includepinned)"
			$argsWinGet += " --include-pinned"
			Write-Verbose "Adding includepinned to argsWinGet: $($argsWinGet)"
		}
		
		Write-Verbose "Final argsWinGet: $($argsWinGet)"
		Write-ADTLogEntry -Message "Final argsWinGet: $($argsWinGet)" -Source "Start-WinGetPackageFM"
		Write-Verbose "Action: $($Action)"
		Write-ADTLogEntry -Message "UserMode: $($UserMode)" -Source "Start-WinGetPackageFM"
		$wingetpath = Resolve-WingetPath -UserMode $UserMode
		If ($proxy -and $UserMode -eq 'Admin') {
			# winget only accepts --proxy when the admin setting ProxyCommandLineOptions is enabled
			$wingetSettings = Invoke-WingetFM -WingetPath $wingetpath -Arguments 'settings export'
			If ($wingetSettings.Output -notmatch '"ProxyCommandLineOptions"\s*:\s*true') {
				$null = Invoke-WingetFM -WingetPath $wingetpath -Arguments 'settings --enable ProxyCommandLineOptions'
			}
		}
		$package = @($id, $name, $moniker, $productcode, $wingetmanifest, $importfile) | Where-Object { $_ } | Select-Object -First 1
		Write-ADTLogEntry -Message "Running winget $Action for [$package]" -Source "Start-WinGetPackageFM"
		If ($Action -eq 'Install') {
			# 0x8A150061 = already installed (--no-upgrade), 0x8A15002B = installed and no newer version
			$result = Start-ADTProcess -FilePath "$wingetpath\winget.exe" -ArgumentList "$Action $argsWinGet" -CreateNoWindow -IgnoreExitCodes '-1978335135', '-1978335189' -PassThru -ErrorAction SilentlyContinue
			If ($result.ExitCode -in @(-1978335135, -1978335189)) {
				Write-ADTLogEntry -Message ("[$package] is already installed, nothing to install (winget exit code 0x{0:X8})" -f $result.ExitCode) -Source "Start-WinGetPackageFM"
			}
		}
		Else {
			$result = Start-ADTProcess -FilePath "$wingetpath\winget.exe" -ArgumentList "$Action $argsWinGet" -CreateNoWindow -PassThru -ErrorAction SilentlyContinue
		}
		$success = $result.ExitCode -in @(0, 1641, 3010, -1978335135, -1978335189)
		If ($PassThru) {
			Write-ADTLogEntry -Message "Done: winget $Action for [$package], exit code $($result.ExitCode)" -Source "Start-WinGetPackageFM"
			Return [PSCustomObject]@{ ExitCode = $result.ExitCode; Success = $success }
		}
		# PSADT ignores -ExitOnProcessFailure for PSAppDeployToolkit.* modules, so the exit code is passed on here
		If ($result.ExitCode -in @(1641, 3010)) {
			(Get-ADTSession).SetExitCode($result.ExitCode)
		}
		ElseIf (-not $success) {
			Close-ADTSession -ExitCode $result.ExitCode
		}
		Write-ADTLogEntry -Message "Done: winget $Action for [$package]" -Source "Start-WinGetPackageFM"
		
	}
		
    End {
        Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}
#endregion

#region Function Invoke-WinGetActionFM
Function Invoke-WinGetActionFM {
    <#
.SYNOPSIS

    Runs a winget action with the mod files around it.

.DESCRIPTION

    Loads the global mod (_WingetFW.ps1) and the app mod (<source>\<id>.ps1) with Import-WingetFWMod, then:
      global Pre, app Pre, winget, app During, global During, app Post or Not, global Post or Not.
    A Pre section that returns $false skips the action with exit code 69002.
    $Settings.<Action> of the app mod is passed to Start-WinGetPackageFM (the command line beats it).
    -ForceRepair runs uninstall and install between the Repair sections.

.PARAMETER UserMode

    Admin or User.

.PARAMETER Action

    Install, Uninstall, upgrade, import or Repair.

.PARAMETER WinGetParameters

    The winget parameters for Start-WinGetPackageFM.

.PARAMETER ForceRepair

    With Repair: uninstall and install instead of winget repair.

.EXAMPLE

    Invoke-WinGetActionFM -UserMode 'Admin' -Action 'Install' -WinGetParameters @{ id = '7zip.7zip'; exact = $true }

.LINK

    https://github.com/ksk-itdk/PSADT-WingetFW
#>

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Admin', 'User')]
        [String]$UserMode,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Install', 'Uninstall', 'upgrade', 'import', 'Repair')]
        [String]$Action,

        [Parameter(Mandatory = $true)]
        [Hashtable]$WinGetParameters,

        [Parameter()]
        [Switch]$ForceRepair
    )

    Begin {
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    Process {
        $sectionNames = @{
            Install   = @('PreInstall', 'Install', 'PostInstall', 'NotInstalled')
            Uninstall = @('PreUninstall', 'Uninstall', 'PostUninstall', 'NotUninstalled')
            Repair    = @('PreRepair', 'Repair', 'PostRepair', 'NotRepaired')
            Upgrade   = @('PreUpgrade', 'Upgrade', 'PostUpgrade', 'NotUpgraded')
            Import    = @('PreImport', $null, 'PostImport', $null)
        }
        $actionName = (Get-Culture).TextInfo.ToTitleCase($Action.ToLowerInvariant())
        $preSection, $duringSection, $postSection, $notSection = $sectionNames[$actionName]

        # The app mod folder is the source: -source, else DefaultSource, else winget
        $modSource = [String]$WinGetParameters['source']
        If (-not $modSource) { $modSource = [String](Get-WingetFWSetting -Name 'DefaultSource' -Config $Script:WingetFWConfig -Default 'winget').Value }
        $modId = If ($actionName -eq 'Import') { '' } Else { [String]$WinGetParameters['id'] }
        $mods = Import-WingetFWMod -Id $modId -Source $modSource -Scope $(If ($UserMode -eq 'Admin') { 'Machine' } Else { 'User' }) -Config $Script:WingetFWConfig -PackagePath (Split-Path -Path $PSScriptRoot -Parent)
        $modSettings = @{}
        If ($mods.App -and $mods.App.Settings[$actionName] -is [Hashtable]) { $modSettings = $mods.App.Settings[$actionName] }
        $preOrder = @(@($mods.Global, $mods.App) | Where-Object { $_ })
        $afterOrder = @(@($mods.App, $mods.Global) | Where-Object { $_ })
        $context = [PSCustomObject]@{ Action = $actionName; Id = $modId; Source = $modSource; UserMode = $UserMode; ForceRepair = [Bool]$ForceRepair; Parameters = $WinGetParameters; ExitCode = $null; Success = $null }

        ForEach ($mod in $preOrder) {
            If ((Invoke-WingetFWModSection -Mod $mod -Section $preSection -Context $context) -eq $false) {
                Write-ADTLogEntry -Message "[$preSection] in the $($mod.Name.ToLower()) mod returned `$false, skipping winget $Action (exit code 69002)" -Source 'Invoke-WinGetActionFM' -Severity 2
                Close-ADTSession -ExitCode 69002
                Return
            }
        }

        If ($ForceRepair -and $actionName -eq 'Repair') {
            Write-ADTLogEntry -Message "ForceRepair: winget uninstall, then winget install" -Source 'Invoke-WinGetActionFM'
            $result = Start-WinGetPackageFM -UserMode $UserMode -Action 'uninstall' -SkipUnsupported -PassThru -ModSettings $modSettings @WinGetParameters
            If ($result.Success) {
                $result = Start-WinGetPackageFM -UserMode $UserMode -Action 'install' -PassThru -ModSettings $modSettings @WinGetParameters
            }
        }
        Else {
            $result = Start-WinGetPackageFM -UserMode $UserMode -Action $Action -PassThru -ModSettings $modSettings @WinGetParameters
        }
        $context.ExitCode = $result.ExitCode
        $context.Success = $result.Success

        If ($duringSection) {
            ForEach ($mod in $afterOrder) { $null = Invoke-WingetFWModSection -Mod $mod -Section $duringSection -Context $context }
        }
        $resultSection = If ($result.Success) { $postSection } Else { $notSection }
        If ($resultSection) {
            ForEach ($mod in $afterOrder) { $null = Invoke-WingetFWModSection -Mod $mod -Section $resultSection -Context $context }
        }

        # PSADT ignores -ExitOnProcessFailure for PSAppDeployToolkit.* modules, so the exit code is passed on here
        If ($result.ExitCode -in @(1641, 3010)) {
            (Get-ADTSession).SetExitCode($result.ExitCode)
        }
        ElseIf (-not $result.Success) {
            Close-ADTSession -ExitCode $result.ExitCode
        }
    }

    End {
        Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}
#endregion

#region Function Invoke-WingetFM
Function Invoke-WingetFM {
    <#
.SYNOPSIS

    Runs a winget helper command (settings, source) and returns the exit code and output.

.DESCRIPTION

    Used for winget calls around the package action. The package action itself runs with Start-ADTProcess.
    Each call is logged as "winget <arguments> -> exit code <code>". winget is stopped after 120 seconds.

.PARAMETER WingetPath

    Folder of winget.exe (Resolve-WingetPath).

.PARAMETER Arguments

    winget arguments.

.OUTPUTS

    PSCustomObject with ExitCode and Output.

.LINK

    https://github.com/ksk-itdk/PSADT-WingetFW
#>

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$WingetPath,

        [Parameter(Mandatory = $true)]
        [String]$Arguments
    )

    $startInfo = New-Object -TypeName System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = Join-Path -Path $WingetPath -ChildPath 'winget.exe'
    $startInfo.Arguments = $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $errorTask = $process.StandardError.ReadToEndAsync()
    $output = $process.StandardOutput.ReadToEnd()
    If (-not $process.WaitForExit(120000)) {
        $process.Kill()
        Write-ADTLogEntry -Message "winget $Arguments did not finish within 120 seconds and was stopped" -Source 'Invoke-WingetFM' -Severity 2
    }
    $output = ($output + $errorTask.Result) -replace '[\b]', ''
    $exitCode = $process.ExitCode
    Write-ADTLogEntry -Message ("winget $Arguments -> exit code $exitCode" + $(If ($exitCode -lt 0) { ' (0x{0:X8})' -f $exitCode })) -Source 'Invoke-WingetFM'
    [PSCustomObject]@{ ExitCode = $exitCode; Output = $output }
}
#endregion

#region Function Add-WingetFWSourceFM
Function Add-WingetFWSourceFM {
    <#
.SYNOPSIS

    Admin mode: adds the REST sources from the Sources setting when they are missing or have another URL.

.DESCRIPTION

    Sources is a list of name = URL (policy HKLM\SOFTWARE\Policies\WingetFW\Sources, local key or config file).
    The names must only contain letters, digits, '.', '_' and '-', the URLs must start with https://.
    A source that can't be added is logged as a warning; the deployment continues.

.LINK

    https://github.com/ksk-itdk/PSADT-WingetFW
#>

    [CmdletBinding()]
    Param ()

    $sourcesSetting = Get-WingetFWSetting -Name 'Sources' -Config $Script:WingetFWConfig
    If ($null -eq $sourcesSetting.Value) { Return }
    If ($sourcesSetting.Value -isnot [System.Collections.IDictionary]) {
        Write-ADTLogEntry -Message "Sources must be a list of name = URL, ignoring it" -Source 'Add-WingetFWSourceFM' -Severity 2
        Return
    }
    Try {
        $wingetpath = Resolve-WingetPath -UserMode 'Admin'
    }
    Catch {
        Write-ADTLogEntry -Message "Sources not added, winget not found: $($_.Exception.Message)" -Source 'Add-WingetFWSourceFM' -Severity 2
        Return
    }
    ForEach ($entry in @($sourcesSetting.Value.GetEnumerator())) {
        $sourceName = [string]$entry.Key
        $sourceUrl = [string]$entry.Value
        If ($sourceName -notmatch '^[\w.-]+$' -or $sourceUrl -notmatch '^https://[^\s"]+$') {
            Write-ADTLogEntry -Message "Skipping source [$sourceName] = [$sourceUrl]: the name may only contain letters, digits, '.', '_' and '-', and the URL must start with https://" -Source 'Add-WingetFWSourceFM' -Severity 2
            Continue
        }
        $export = Invoke-WingetFM -WingetPath $wingetpath -Arguments "source export --name $sourceName"
        If ($export.ExitCode -eq 0) {
            $currentUrl = $null
            Try {
                $json = $export.Output.Substring($export.Output.IndexOf('{'), $export.Output.LastIndexOf('}') - $export.Output.IndexOf('{') + 1)
                $currentUrl = ($json | ConvertFrom-Json).Arg
            }
            Catch {
                Write-ADTLogEntry -Message "Could not read the URL of source [$sourceName]: $($_.Exception.Message)" -Source 'Add-WingetFWSourceFM' -Severity 2
            }
            If ($currentUrl -eq $sourceUrl) {
                Write-ADTLogEntry -Message "Source [$sourceName] already added with [$sourceUrl]" -Source 'Add-WingetFWSourceFM'
                Continue
            }
            Write-ADTLogEntry -Message "Source [$sourceName] has URL [$currentUrl], replacing it with [$sourceUrl]" -Source 'Add-WingetFWSourceFM'
            $null = Invoke-WingetFM -WingetPath $wingetpath -Arguments "source remove --name $sourceName"
        }
        $add = Invoke-WingetFM -WingetPath $wingetpath -Arguments "source add --name $sourceName --arg $sourceUrl --type Microsoft.Rest --accept-source-agreements --disable-interactivity"
        If ($add.ExitCode -eq 0) {
            Write-ADTLogEntry -Message "Source [$sourceName] added with [$sourceUrl]" -Source 'Add-WingetFWSourceFM'
        }
        Else {
            $lastLine = @($add.Output -split '\r?\n' | Where-Object { $_.Trim() }) | Select-Object -Last 1
            Write-ADTLogEntry -Message "Could not add source [$sourceName] with [$sourceUrl]: $lastLine" -Source 'Add-WingetFWSourceFM' -Severity 2
        }
    }
}
#endregion

#region Function Resolve-WingetPath
Function Resolve-WingetPath {
    <#
.SYNOPSIS

    Find the path for Winget

.PARAMETER UserMode

    Specifies if the check is running in user or admin mode. Allowed options: User, Admin
	
	User - will check for Winget in appdata.
	Admin - will check for Winget in C:\Program Files\WindowsApps.

.INPUTS

None

You cannot pipe objects to this function.

.OUTPUTS

None

This function return the path of winget.

.EXAMPLE

    Will gwt the path of WinGet for admin/system, do not work with a user account

    PS C:\>Resolve-WingetPath -UserMode 'Admin'

.EXAMPLE

    Will gwt the path of WinGet for user, do not work with system account

    PS C:\>Resolve-WingetPath -UserMode 'User'

.NOTES

.LINK

    https://github.com/ksk-itdk/PSADT-WingetFW
#>

    [CmdletBinding()]
    Param (
		[Parameter( Mandatory = $false, Position = 0, HelpMessage = 'One or more user names (ex: BUILTIN\Users, DOMAIN\Admin). If you want to use SID, prefix it with an asterisk * (ex: *S-1-5-18)',ParameterSetName = 'AdminMode')]
        [ValidateSet('Admin', 'User')]
        [String]$UserMode = 'Admin'	
    )

    Begin {
        # Initialize function.
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    Process {
		Write-ADTLogEntry -Message "Starting check of WinGet" -Source 'Resolve-WingetPath'
		If($UserMode -eq "Admin"){
			# Folder names sort as text (1.100 < 1.29), so pick the newest by version
			$ResolveWingetPath = Get-ChildItem -Path 'C:\Program Files\WindowsApps' -Directory -Filter 'Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe' -ErrorAction SilentlyContinue |
				Where-Object { Test-Path (Join-Path $_.FullName 'winget.exe') } |
				Sort-Object { [version]($_.Name -split '_')[1] } | Select-Object -Last 1
			if($ResolveWingetPath){
				$WingetPath = $ResolveWingetPath.FullName
			}
		}
		If($UserMode -eq "User"){
			# At a user's first logon Windows registers App Installer (winget) asynchronously, so it can be missing for a short time
			For ($attempt = 1; $attempt -le 5; $attempt++) {
				$ResolveWingetPath = Resolve-Path "$env:LOCALAPPDATA\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller*\winget.exe" -ErrorAction SilentlyContinue
				If ($ResolveWingetPath) { Break }
				If ($attempt -eq 1) {
					Write-ADTLogEntry -Message "winget not found for the user, requesting App Installer registration" -Source 'Resolve-WingetPath' -Severity 2
					Try {
						Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction Stop
					}
					Catch {
						Write-ADTLogEntry -Message "App Installer registration failed: $($_.Exception.Message)" -Source 'Resolve-WingetPath' -Severity 2
					}
					Continue
				}
				If ($attempt -lt 5) {
					Write-ADTLogEntry -Message "winget not found yet (attempt $attempt of 5), waiting 5 seconds" -Source 'Resolve-WingetPath' -Severity 2
					Start-Sleep -Seconds 5
				}
			}
			if($ResolveWingetPath){
				$WingetPath = Split-Path -Path $ResolveWingetPath[-1].Path -Parent
			}
		}
		if($ResolveWingetPath -EQ $null){
			Write-ADTLogEntry -Message "ERROR, path for winget not found" -Source 'Resolve-WingetPath'
			Throw "Path for winget not found"
			Break
		}
		Write-ADTLogEntry -Message "Winget path: $($WingetPath)" -Source 'Resolve-WingetPath'
		return $WingetPath
	}
		
    End {
        Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}
#endregion

##*===============================================
##* MARK: SCRIPT BODY
##*===============================================

# Announce successful importation of module.
Write-ADTLogEntry -Message "Module [$($MyInvocation.MyCommand.ScriptBlock.Module.Name)] imported successfully." -ScriptSection Initialization
