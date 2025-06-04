<#
.SYNOPSIS
WINGETFW version 4.0.2
PSAppDeployToolkit - Provides the ability to extend and customise the toolkit by adding your own functions that can be re-used.

.DESCRIPTION

This script is a template that allows you to extend the toolkit with your own custom functions.

This script is dot-sourced by the AppDeployToolkitMain.ps1 script which contains the logic and functions required to install or uninstall an application.

PSApppDeployToolkit is licensed under the GNU LGPLv3 License - (C) 2023 PSAppDeployToolkit Team (Sean Lillis, Dan Cunningham and Muhammad Mashwani).

This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the
Free Software Foundation, either version 3 of the License, or any later version. This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
for more details. You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.

.EXAMPLE

powershell.exe -File .\AppDeployToolkitHelp.ps1

.INPUTS

None

You cannot pipe objects to this script.

.OUTPUTS

None

This script does not generate any output.

.NOTES

.LINK

https://psappdeploytoolkit.com
https://github.com/ksk-itdk/PSADT-WingetFW
#>


[CmdletBinding()]
Param (
)

##*===============================================
##* VARIABLE DECLARATION
##*===============================================

# Variables: Script
[string]$appDeployToolkitExtName = 'PSAppDeployToolkitExt'
[string]$appDeployExtScriptFriendlyName = 'App Deploy Toolkit Extensions'
[version]$appDeployExtScriptVersion = [version]'3.9.3'
[string]$appDeployExtScriptDate = '02/05/2023'
[hashtable]$appDeployExtScriptParameters = $PSBoundParameters

##*===============================================
##* FUNCTION LISTINGS
##*===============================================

# <Your custom functions go here>
#region Function Check-WinGetFM
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
        ## Get the name of this function and write header
        [String]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
        Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
    }

    Process {
		
		Write-Log -Message "UserMode $UserMode" -Source 'Install-WinGetFM' -LogType 'CMTrace'
		$AppInstaller = Check-WinGetFM -UserMode $UserMode
		If($UserMode -eq "Admin"){
			
			If($AppInstaller.WingetVersion -lt $Version) {
				
				Write-Log -Message "Winget is not installed, trying to install latest version from Github" -Source 'Install-WinGetFM' -LogType 'CMTrace'
				
				Try {
					
					Write-Log -Message "Creating Winget Packages Folder" -Source 'Install-WinGetFM' -LogType 'CMTrace'
					
					if (!(Test-Path -Path C:\ProgramData\WinGetPackages)) {
						New-Item -Path C:\ProgramData\WinGetPackages -Force -ItemType Directory
					}
					Switch ($InstallMethod) {
						'Online' {
							#Set-Location C:\ProgramData\WinGetPackages
							
							#Downloading Packagefiles
							Write-Log -Message "Setting ProgressPreference to SilentlyContinue" -Source 'Install-WinGetFM' -LogType 'CMTrace'
							$ProgressPreference = 'SilentlyContinue'
							#Microsoft.UI.Xaml - newest
							Write-Log -Message "Downloading microsoft.ui.xaml.newest.zip from https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/" -Source 'Install-WinGetFM' -LogType 'CMTrace'
							Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/" -OutFile "C:\ProgramData\WinGetPackages\microsoft.ui.xaml.newest.zip"
							Write-Log -Message "Exstract C:\ProgramData\WinGetPackages\microsoft.ui.xaml.newest.zip" -Source 'Install-WinGetFM' -LogType 'CMTrace'
							Expand-Archive -LiteralPath "C:\ProgramData\WinGetPackages\microsoft.ui.xaml.newest.zip" -DestinationPath "C:\ProgramData\WinGetPackages\microsoft.ui.xaml.newest" -Force
							#Microsoft.VCLibs.140.00.UWPDesktop
							Write-Log -Message "Downloading Microsoft.VCLibs.x64.14.00.Desktop.appx from https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -Source 'Install-WinGetFM' -LogType 'CMTrace'
							Invoke-WebRequest -Uri "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -OutFile "C:\ProgramData\WinGetPackages\Microsoft.VCLibs.x64.14.00.Desktop.appx"
							#Winget
							Write-Log -Message "Downloading Winget.msixbundle from https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -Source 'Install-WinGetFM' -LogType 'CMTrace'
							Invoke-WebRequest -Uri "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -OutFile "C:\ProgramData\WinGetPackages\Winget.msixbundle"
							Write-Log -Message 'Finding the MicrosoftUIXaml Version and shave the it to $MicrosoftUIXamlVersion' -Source 'Install-WinGetFM' -LogType 'CMTrace'
							$MicrosoftUIXamlVersion = Get-ChildItem C:\ProgramData\WinGetPackages\microsoft.ui.xaml.newest\tools\AppX\x64\Release -recurse | where {$_.name -like "Microsoft.UI.Xaml.*"} | select name
							#Installing dependencies + Winget
							Write-Log -Message "Installing winget and Dependency Package" -Source 'Install-WinGetFM' -LogType 'CMTrace'
							Add-ProvisionedAppxPackage -online -PackagePath:C:\ProgramData\WinGetPackages\Winget.msixbundle -DependencyPackagePath C:\ProgramData\WinGetPackages\Microsoft.VCLibs.x64.14.00.Desktop.appx,C:\ProgramData\WinGetPackages\microsoft.ui.xaml.newest\tools\AppX\x64\Release\$($MicrosoftUIXamlVersion.name) -SkipLicense
							
						}
						'Local' {
							Write-Log -Message "ERROR Local install NOT ready to use" -Source 'Install-WinGetFM' -LogType 'CMTrace'
							Throw "Failed to install Winget"
							Break
						}
						'Wingetmodule' {
							Write-Log -Message "ERROR Local Wingetmodule NOT ready to use" -Source 'Install-WinGetFM' -LogType 'CMTrace'
							Throw "Failed to install Winget"
							Break
						}
					}
					
					Write-Log -Message "Starting sleep for Winget to initiate" -Source 'Install-WinGetFM' -LogType 'CMTrace'
					Start-Sleep 2
				}
				Catch {
					Throw "Failed to install Winget"
					Write-Log -Message "$Error[0].Exception" -Source 'Install-WinGetFM' -LogType 'CMTrace'
					Break
				}
			
			}Else{
				Write-Log -Message "Winget already installed, moving on" -Source 'Install-WinGetFM' -LogType 'CMTrace'
			}
        }
		If($UserMode -eq "User"){
			Write-Log -Message "UserMode $Mode" -Source 'Install-WinGetFM' -LogType 'CMTrace'
            $AppInstaller = Get-AppxPackage | Where-Object Name -eq Microsoft.DesktopAppInstaller
			If($AppInstaller.WingetVersion -lt $Version) {
				Write-Log -Message "Winget is not installed" -Source 'Install-WinGetFM' -LogType 'CMTrace'
			}Else{
				Write-Log -Message "Winget already installed, moving on" -Source 'Install-WinGetFM' -LogType 'CMTrace'
			}
        }
	}
		
    End {
        Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
    }
}
#endregion

#region Function Check-WinGetFM
Function Check-WinGetFM {
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

    PS C:\>Check-WinGetFM -UserMode 'Admin'

.EXAMPLE

    Will check the WinGet version for user, do not work with system account

    PS C:\>Check-WinGetFM -UserMode 'User'

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
        ## Get the name of this function and write header
        [String]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
        Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
    }

    Process {
		Write-Log -Message "Starting check of WinGet" -Source 'Check-WinGetFM' -LogType 'CMTrace'
		If($UserMode -eq "Admin"){
			$AppInstaller = Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq Microsoft.DesktopAppInstaller
			Write-Log -Message "Checking install version $(($AppInstaller).Version)" -Source 'Check-WinGetFM-Admin' -LogType 'CMTrace'
		}
		If($UserMode -eq "User"){
			$AppInstaller = Get-AppxPackage | Where-Object Name -eq Microsoft.DesktopAppInstaller
			Write-Log -Message "Checking install version $(($AppInstaller).Version)" -Source 'Check-WinGetFM-User' -LogType 'CMTrace'
		}
		$myObject = @()
		If($AppInstaller -eq $null){
			$myObject = [PSCustomObject]@{
				"WingetVersion" = 0
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
        Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
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

    Specifies if you need to install, uninstall, upgrade or import.
	
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

.PARAMETER wait

    Prompts the user to press any key before exiting.

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

    [CmdletBinding(DefaultParameterSetName = 'AdminMode')]
    Param (
		[Parameter( Mandatory = $false, Position = 0, HelpMessage = 'Specifies if the script is running in user or admin mode. Allowed options: User, Admin',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 0, HelpMessage = 'Specifies if the script is running in user or admin mode. Allowed options: User, Admin',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 0, HelpMessage = 'Specifies if the script is running in user or admin mode. Allowed options: User, Admin',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 0, HelpMessage = 'Specifies if the script is running in user or admin mode. Allowed options: User, Admin',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 0, HelpMessage = 'Specifies if the script is running in user or admin mode. Allowed options: User, Admin',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 0, HelpMessage = 'Specifies if the script is running in user or admin mode. Allowed options: User, Admin',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 0, HelpMessage = 'Specifies if the script is running in user or admin mode. Allowed options: User, Admin',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 0, HelpMessage = 'Specifies if the script is running in user or admin mode. Allowed options: User, Admin',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 0, HelpMessage = 'Specifies if the script is running in user or admin mode. Allowed options: User, Admin',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 0, HelpMessage = 'Specifies if the script is running in user or admin mode. Allowed options: User, Admin',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 0, HelpMessage = 'Specifies if the script is running in user or admin mode. Allowed options: User, Admin',ParameterSetName = 'Moniker')]
        [ValidateSet('Admin', 'User')]
        [String]$UserMode = $Mode,
		
		[Parameter( Mandatory = $false, Position = 1, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 1, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 1, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 1, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 1, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 1, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 1, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 1, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 1, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 1, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 1, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.',ParameterSetName = 'Moniker')]
		[ValidateSet('Install', 'Uninstall', 'upgrade', 'import')]
        [String]$Action,
		
		[Parameter( Mandatory = $false, Position = 2, HelpMessage = 'Must be followed by the path to the manifest (YAML) file. You can use the manifest to run the install experience from a local YAML file.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 2, HelpMessage = 'Must be followed by the path to the manifest (YAML) file. You can use the manifest to run the install experience from a local YAML file.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 2, HelpMessage = 'Must be followed by the path to the manifest (YAML) file. You can use the manifest to run the install experience from a local YAML file.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 2, HelpMessage = 'Must be followed by the path to the manifest (YAML) file. You can use the manifest to run the install experience from a local YAML file.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 2, HelpMessage = 'Must be followed by the path to the manifest (YAML) file. You can use the manifest to run the install experience from a local YAML file.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 2, HelpMessage = 'Must be followed by the path to the manifest (YAML) file. You can use the manifest to run the install experience from a local YAML file.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 2, HelpMessage = 'Must be followed by the path to the manifest (YAML) file. You can use the manifest to run the install experience from a local YAML file.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 2, HelpMessage = 'Must be followed by the path to the manifest (YAML) file. You can use the manifest to run the install experience from a local YAML file.',ParameterSetName = 'Manifest')]
        [String]$wingetmanifest,
		
		[Parameter( Mandatory = $false, Position = 3, HelpMessage = 'Limits the install to the ID of the application.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 3, HelpMessage = 'Limits the install to the ID of the application.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 3, HelpMessage = 'Limits the install to the ID of the application.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 3, HelpMessage = 'Limits the install to the ID of the application.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 3, HelpMessage = 'Limits the install to the ID of the application.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 3, HelpMessage = 'Limits the install to the ID of the application.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 3, HelpMessage = 'Limits the install to the ID of the application.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 3, HelpMessage = 'Limits the install to the ID of the application.',ParameterSetName = 'ID')]
        [String]$id,
		
		[Parameter( Mandatory = $false, Position = 4, HelpMessage = 'Limits the search to the name of the application.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 4, HelpMessage = 'Limits the search to the name of the application.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 4, HelpMessage = 'Limits the search to the name of the application.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 4, HelpMessage = 'Limits the search to the name of the application.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 4, HelpMessage = 'Limits the search to the name of the application.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 4, HelpMessage = 'Limits the search to the name of the application.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 4, HelpMessage = 'Limits the search to the name of the application.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 4, HelpMessage = 'Limits the search to the name of the application.',ParameterSetName = 'Name')]
        [String]$name,
		
		[Parameter( Mandatory = $false, Position = 5, HelpMessage = 'Limits the search to the moniker listed for the application.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 5, HelpMessage = 'Limits the search to the moniker listed for the application.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 5, HelpMessage = 'Limits the search to the moniker listed for the application.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 5, HelpMessage = 'Limits the search to the moniker listed for the application.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 5, HelpMessage = 'Limits the search to the moniker listed for the application.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 5, HelpMessage = 'Limits the search to the moniker listed for the application.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 5, HelpMessage = 'Limits the search to the moniker listed for the application.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 5, HelpMessage = 'Limits the search to the moniker listed for the application.',ParameterSetName = 'Moniker')]
        [String]$moniker,
		
		[Parameter( Mandatory = $false, Position = 6, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 6, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 6, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 6, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 6, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 6, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 6, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 6, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 6, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 6, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 6, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.',ParameterSetName = 'Moniker')]
        [String]$version,
		
		[Parameter( Mandatory = $false, Position = 7, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 7, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 7, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 7, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 7, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 7, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 7, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 7, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 7, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 7, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 7, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.',ParameterSetName = 'Moniker')]
        [String]$source,
		
		[Parameter( Mandatory = $false, Position = 8, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 8, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 8, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 8, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 8, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 8, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 8, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 8, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 8, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 8, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 8, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.',ParameterSetName = 'Moniker')]
		[ValidateSet('Any', 'User', 'Machine', 'UserOrUnknown', 'SystemOrUnknown')]
        [String]$scope,
		
		[Parameter( Mandatory = $false, Position = 9, HelpMessage = 'Select the architecture to install.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 9, HelpMessage = 'Select the architecture to install.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 9, HelpMessage = 'Select the architecture to install.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 9, HelpMessage = 'Select the architecture to install.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 9, HelpMessage = 'Select the architecture to install.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 9, HelpMessage = 'Select the architecture to install.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 9, HelpMessage = 'Select the architecture to install.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 9, HelpMessage = 'Select the architecture to install.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 9, HelpMessage = 'Select the architecture to install.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 9, HelpMessage = 'Select the architecture to install.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 9, HelpMessage = 'Select the architecture to install.',ParameterSetName = 'Moniker')]
		[ValidateSet('Default', 'X86', 'Arm', 'X64', 'Arm64')]
        [String]$architecture,
		
		[Parameter( Mandatory = $false, Position = 10, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 10, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 10, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 10, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 10, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 10, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 10, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 10, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 10, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 10, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 10, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.',ParameterSetName = 'Moniker')]
		[ValidateSet('Default', 'Inno', 'Wix', 'Msi', 'Nullsoft', 'Zip', 'Msix', 'Exe', 'Burn', 'MSStore', 'Portable')]
        [String]$installertype,
		
		[Parameter( Mandatory = $false, Position = 11, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 11, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 11, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 11, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 11, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 11, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 11, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 11, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 11, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 11, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 11, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.',ParameterSetName = 'Moniker')]
        [Switch]$exact,
		
		[Parameter( Mandatory = $false, Position = 12, HelpMessage = 'Runs the installer in interactive mode. The default experience shows installer progress.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 12, HelpMessage = 'Runs the installer in interactive mode. The default experience shows installer progress.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 12, HelpMessage = 'Runs the installer in interactive mode. The default experience shows installer progress.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 12, HelpMessage = 'Runs the installer in interactive mode. The default experience shows installer progress.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 12, HelpMessage = 'Runs the installer in interactive mode. The default experience shows installer progress.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 12, HelpMessage = 'Runs the installer in interactive mode. The default experience shows installer progress.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 12, HelpMessage = 'Runs the installer in interactive mode. The default experience shows installer progress.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 12, HelpMessage = 'Runs the installer in interactive mode. The default experience shows installer progress.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 12, HelpMessage = 'Runs the installer in interactive mode. The default experience shows installer progress.',ParameterSetName = 'Moniker')]
        [Switch]$interactive,
		
		[Parameter( Mandatory = $false, Position = 13, HelpMessage = 'Runs the installer in silent mode. This suppresses all UI. The default experience shows installer progress.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 13, HelpMessage = 'Runs the installer in silent mode. This suppresses all UI. The default experience shows installer progress.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 13, HelpMessage = 'Runs the installer in silent mode. This suppresses all UI. The default experience shows installer progress.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 13, HelpMessage = 'Runs the installer in silent mode. This suppresses all UI. The default experience shows installer progress.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 13, HelpMessage = 'Runs the installer in silent mode. This suppresses all UI. The default experience shows installer progress.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 13, HelpMessage = 'Runs the installer in silent mode. This suppresses all UI. The default experience shows installer progress.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 13, HelpMessage = 'Runs the installer in silent mode. This suppresses all UI. The default experience shows installer progress.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 13, HelpMessage = 'Runs the installer in silent mode. This suppresses all UI. The default experience shows installer progress.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 13, HelpMessage = 'Runs the installer in silent mode. This suppresses all UI. The default experience shows installer progress.',ParameterSetName = 'Moniker')]
        [Switch]$silent,
		
		[Parameter( Mandatory = $false, Position = 14, HelpMessage = 'Specifies which locale to use (BCP47 format).',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 14, HelpMessage = 'Specifies which locale to use (BCP47 format).',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 14, HelpMessage = 'Specifies which locale to use (BCP47 format).',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 14, HelpMessage = 'Specifies which locale to use (BCP47 format).',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 14, HelpMessage = 'Specifies which locale to use (BCP47 format).',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 14, HelpMessage = 'Specifies which locale to use (BCP47 format).',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 14, HelpMessage = 'Specifies which locale to use (BCP47 format).',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 14, HelpMessage = 'Specifies which locale to use (BCP47 format).',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 14, HelpMessage = 'Specifies which locale to use (BCP47 format).',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 14, HelpMessage = 'Specifies which locale to use (BCP47 format).',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 14, HelpMessage = 'Specifies which locale to use (BCP47 format).',ParameterSetName = 'Moniker')]
        [String]$locale,
		
		[Parameter( Mandatory = $false, Position = 15, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 15, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 15, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 15, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 15, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 15, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 15, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 15, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 15, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 15, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 15, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.',ParameterSetName = 'Moniker')]
        [String]$log,
		
		[Parameter( Mandatory = $false, Position = 16, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 16, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 16, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 16, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 16, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 16, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 16, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 16, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 16, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 16, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 16, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.',ParameterSetName = 'Moniker')]
        [String]$custom,
		
		[Parameter( Mandatory = $false, Position = 17, HelpMessage = 'A string that will be passed directly to the installer.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 17, HelpMessage = 'A string that will be passed directly to the installer.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 17, HelpMessage = 'A string that will be passed directly to the installer.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 17, HelpMessage = 'A string that will be passed directly to the installer.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 17, HelpMessage = 'A string that will be passed directly to the installer.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 17, HelpMessage = 'A string that will be passed directly to the installer.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 17, HelpMessage = 'A string that will be passed directly to the installer.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 17, HelpMessage = 'A string that will be passed directly to the installer.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 17, HelpMessage = 'A string that will be passed directly to the installer.',ParameterSetName = 'Moniker')]
        [String]$override,
		
		[Parameter( Mandatory = $false, Position = 18, HelpMessage = 'Location to install to (if supported).',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 18, HelpMessage = 'Location to install to (if supported).',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 18, HelpMessage = 'Location to install to (if supported).',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 18, HelpMessage = 'Location to install to (if supported).',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 18, HelpMessage = 'Location to install to (if supported).',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 18, HelpMessage = 'Location to install to (if supported).',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 18, HelpMessage = 'Location to install to (if supported).',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 18, HelpMessage = 'Location to install to (if supported).',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 18, HelpMessage = 'Location to install to (if supported).',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 18, HelpMessage = 'Location to install to (if supported).',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 18, HelpMessage = 'Location to install to (if supported).',ParameterSetName = 'Moniker')]
        [String]$location,
		
		[Parameter( Mandatory = $false, Position = 19, HelpMessage = 'Ignore the installer hash check failure. Not recommended.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 19, HelpMessage = 'Ignore the installer hash check failure. Not recommended.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 19, HelpMessage = 'Ignore the installer hash check failure. Not recommended.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 19, HelpMessage = 'Ignore the installer hash check failure. Not recommended.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 19, HelpMessage = 'Ignore the installer hash check failure. Not recommended.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 19, HelpMessage = 'Ignore the installer hash check failure. Not recommended.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 19, HelpMessage = 'Ignore the installer hash check failure. Not recommended.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 19, HelpMessage = 'Ignore the installer hash check failure. Not recommended.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 19, HelpMessage = 'Ignore the installer hash check failure. Not recommended.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 19, HelpMessage = 'Ignore the installer hash check failure. Not recommended.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 19, HelpMessage = 'Ignore the installer hash check failure. Not recommended.',ParameterSetName = 'Moniker')]
        [Switch]$ignoresecurityhash,
		
		[Parameter( Mandatory = $false, Position = 20, HelpMessage = 'Allows a reboot if applicable.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 20, HelpMessage = 'Allows a reboot if applicable.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 20, HelpMessage = 'Allows a reboot if applicable.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 20, HelpMessage = 'Allows a reboot if applicable.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 20, HelpMessage = 'Allows a reboot if applicable.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 20, HelpMessage = 'Allows a reboot if applicable.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 20, HelpMessage = 'Allows a reboot if applicable.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 20, HelpMessage = 'Allows a reboot if applicable.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 20, HelpMessage = 'Allows a reboot if applicable.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 20, HelpMessage = 'Allows a reboot if applicable.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 20, HelpMessage = 'Allows a reboot if applicable.',ParameterSetName = 'Moniker')]
        [Switch]$allowreboot,
		
		[Parameter( Mandatory = $false, Position = 21, HelpMessage = 'Skips processing package dependencies and Windows features.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 21, HelpMessage = 'Skips processing package dependencies and Windows features.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 21, HelpMessage = 'Skips processing package dependencies and Windows features.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 21, HelpMessage = 'Skips processing package dependencies and Windows features.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 21, HelpMessage = 'Skips processing package dependencies and Windows features.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 21, HelpMessage = 'Skips processing package dependencies and Windows features.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 21, HelpMessage = 'Skips processing package dependencies and Windows features.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 21, HelpMessage = 'Skips processing package dependencies and Windows features.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 21, HelpMessage = 'Skips processing package dependencies and Windows features.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 21, HelpMessage = 'Skips processing package dependencies and Windows features.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 21, HelpMessage = 'Skips processing package dependencies and Windows features.',ParameterSetName = 'Moniker')]
        [Switch]$skipdependencies,
		
		[Parameter( Mandatory = $false, Position = 22, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 22, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 22, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 22, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 22, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 22, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 22, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 22, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 22, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 22, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 22, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.',ParameterSetName = 'Moniker')]
        [Switch]$ignorelocalarchivemalwarescan,
		
		[Parameter( Mandatory = $false, Position = 23, HelpMessage = 'Find package dependencies using the specified source.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 23, HelpMessage = 'Find package dependencies using the specified source.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 23, HelpMessage = 'Find package dependencies using the specified source.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 23, HelpMessage = 'Find package dependencies using the specified source.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 23, HelpMessage = 'Find package dependencies using the specified source.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 23, HelpMessage = 'Find package dependencies using the specified source.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 23, HelpMessage = 'Find package dependencies using the specified source.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 23, HelpMessage = 'Find package dependencies using the specified source.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 23, HelpMessage = 'Find package dependencies using the specified source.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 23, HelpMessage = 'Find package dependencies using the specified source.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 23, HelpMessage = 'Find package dependencies using the specified source.',ParameterSetName = 'Moniker')]
        [String]$dependencysource,
		
		[Parameter( Mandatory = $false, Position = 24, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 24, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 24, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 24, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 24, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 24, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 24, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 24, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 24, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 24, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 24, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.',ParameterSetName = 'Moniker')]
        [Switch]$acceptpackageagreements = $true,
		
		[Parameter( Mandatory = $false, Position = 25, HelpMessage = 'Skips upgrade if an installed version already exists.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 25, HelpMessage = 'Skips upgrade if an installed version already exists.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 25, HelpMessage = 'Skips upgrade if an installed version already exists.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 25, HelpMessage = 'Skips upgrade if an installed version already exists.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 25, HelpMessage = 'Skips upgrade if an installed version already exists.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 25, HelpMessage = 'Skips upgrade if an installed version already exists.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 25, HelpMessage = 'Skips upgrade if an installed version already exists.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 25, HelpMessage = 'Skips upgrade if an installed version already exists.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 25, HelpMessage = 'Skips upgrade if an installed version already exists.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 25, HelpMessage = 'Skips upgrade if an installed version already exists.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 25, HelpMessage = 'Skips upgrade if an installed version already exists.',ParameterSetName = 'Moniker')]
        [Switch]$noupgrade,
		
		[Parameter( Mandatory = $false, Position = 26, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 26, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 26, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 26, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 26, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 26, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 26, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 26, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 26, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 26, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 26, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.',ParameterSetName = 'Moniker')]
        [String]$header,
		
		[Parameter( Mandatory = $false, Position = 27, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 27, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 27, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 27, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 27, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 27, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 27, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 27, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 27, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 27, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 27, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).',ParameterSetName = 'Moniker')]
		[ValidateSet('silent', 'silentPreferred', 'interactive')]
        [String]$authenticationmode,
		
		[Parameter( Mandatory = $false, Position = 28, HelpMessage = 'Specify the account to be used for authentication.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 28, HelpMessage = 'Specify the account to be used for authentication.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 28, HelpMessage = 'Specify the account to be used for authentication.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 28, HelpMessage = 'Specify the account to be used for authentication.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 28, HelpMessage = 'Specify the account to be used for authentication.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 28, HelpMessage = 'Specify the account to be used for authentication.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 28, HelpMessage = 'Specify the account to be used for authentication.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 28, HelpMessage = 'Specify the account to be used for authentication.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 28, HelpMessage = 'Specify the account to be used for authentication.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 28, HelpMessage = 'Specify the account to be used for authentication.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 28, HelpMessage = 'Specify the account to be used for authentication.',ParameterSetName = 'Moniker')]
        [String]$authenticationaccount,
		
		[Parameter( Mandatory = $false, Position = 29, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 29, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 29, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 29, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 29, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 29, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 29, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 29, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 29, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 29, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 29, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.',ParameterSetName = 'Moniker')]
        [Switch]$acceptsourceagreements = $true,
		
		[Parameter( Mandatory = $false, Position = 30, HelpMessage = 'The value to rename the executable file (portable).',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 30, HelpMessage = 'The value to rename the executable file (portable).',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 30, HelpMessage = 'The value to rename the executable file (portable).',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 30, HelpMessage = 'The value to rename the executable file (portable).',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 30, HelpMessage = 'The value to rename the executable file (portable).',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 30, HelpMessage = 'The value to rename the executable file (portable).',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 30, HelpMessage = 'The value to rename the executable file (portable).',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 30, HelpMessage = 'The value to rename the executable file (portable).',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 30, HelpMessage = 'The value to rename the executable file (portable).',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 30, HelpMessage = 'The value to rename the executable file (portable).',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 30, HelpMessage = 'The value to rename the executable file (portable).',ParameterSetName = 'Moniker')]
        [String]$rename,
		
		[Parameter( Mandatory = $false, Position = 31, HelpMessage = 'Uninstall the previous version of the package during upgrade.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 31, HelpMessage = 'Uninstall the previous version of the package during upgrade.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 31, HelpMessage = 'Uninstall the previous version of the package during upgrade.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 31, HelpMessage = 'Uninstall the previous version of the package during upgrade.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 31, HelpMessage = 'Uninstall the previous version of the package during upgrade.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 31, HelpMessage = 'Uninstall the previous version of the package during upgrade.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 31, HelpMessage = 'Uninstall the previous version of the package during upgrade.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 31, HelpMessage = 'Uninstall the previous version of the package during upgrade.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 31, HelpMessage = 'Uninstall the previous version of the package during upgrade.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 31, HelpMessage = 'Uninstall the previous version of the package during upgrade.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 31, HelpMessage = 'Uninstall the previous version of the package during upgrade.',ParameterSetName = 'Moniker')]
        [Switch]$uninstallprevious,
		
		[Parameter( Mandatory = $false, Position = 32, HelpMessage = 'Direct run the command and continue with non security related issues.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 32, HelpMessage = 'Direct run the command and continue with non security related issues.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 32, HelpMessage = 'Direct run the command and continue with non security related issues.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 32, HelpMessage = 'Direct run the command and continue with non security related issues.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 32, HelpMessage = 'Direct run the command and continue with non security related issues.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 32, HelpMessage = 'Direct run the command and continue with non security related issues.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 32, HelpMessage = 'Direct run the command and continue with non security related issues.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 32, HelpMessage = 'Direct run the command and continue with non security related issues.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 32, HelpMessage = 'Direct run the command and continue with non security related issues.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 32, HelpMessage = 'Direct run the command and continue with non security related issues.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 32, HelpMessage = 'Direct run the command and continue with non security related issues.',ParameterSetName = 'Moniker')]
        [Switch]$force,
		
		[Parameter( Mandatory = $false, Position = 33, HelpMessage = 'Prompts the user to press any key before exiting.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 33, HelpMessage = 'Prompts the user to press any key before exiting.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 33, HelpMessage = 'Prompts the user to press any key before exiting.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 33, HelpMessage = 'Prompts the user to press any key before exiting.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 33, HelpMessage = 'Prompts the user to press any key before exiting.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 33, HelpMessage = 'Prompts the user to press any key before exiting.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 33, HelpMessage = 'Prompts the user to press any key before exiting.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 33, HelpMessage = 'Prompts the user to press any key before exiting.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 33, HelpMessage = 'Prompts the user to press any key before exiting.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 33, HelpMessage = 'Prompts the user to press any key before exiting.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 33, HelpMessage = 'Prompts the user to press any key before exiting.',ParameterSetName = 'Moniker')]
        [Switch]$wait,
		
		[Parameter( Mandatory = $false, Position = 34, HelpMessage = 'Used to override the logging setting and create a verbose log.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 34, HelpMessage = 'Used to override the logging setting and create a verbose log.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 34, HelpMessage = 'Used to override the logging setting and create a verbose log.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 34, HelpMessage = 'Used to override the logging setting and create a verbose log.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 34, HelpMessage = 'Used to override the logging setting and create a verbose log.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 34, HelpMessage = 'Used to override the logging setting and create a verbose log.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 34, HelpMessage = 'Used to override the logging setting and create a verbose log.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 34, HelpMessage = 'Used to override the logging setting and create a verbose log.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 34, HelpMessage = 'Used to override the logging setting and create a verbose log.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 34, HelpMessage = 'Used to override the logging setting and create a verbose log.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 34, HelpMessage = 'Used to override the logging setting and create a verbose log.',ParameterSetName = 'Moniker')]
        [Switch]$enableverbose,
		
		[Parameter( Mandatory = $false, Position = 35, HelpMessage = 'Suppresses warning outputs.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 35, HelpMessage = 'Suppresses warning outputs.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 35, HelpMessage = 'Suppresses warning outputs.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 35, HelpMessage = 'Suppresses warning outputs.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 35, HelpMessage = 'Suppresses warning outputs.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 35, HelpMessage = 'Suppresses warning outputs.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 35, HelpMessage = 'Suppresses warning outputs.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 35, HelpMessage = 'Suppresses warning outputs.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 35, HelpMessage = 'Suppresses warning outputs.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 35, HelpMessage = 'Suppresses warning outputs.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 35, HelpMessage = 'Suppresses warning outputs.',ParameterSetName = 'Moniker')]
        [Switch]$ignorewarnings,
		
		[Parameter( Mandatory = $false, Position = 36, HelpMessage = 'Disable interactive prompts.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 36, HelpMessage = 'Disable interactive prompts.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 36, HelpMessage = 'Disable interactive prompts.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 36, HelpMessage = 'Disable interactive prompts.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 36, HelpMessage = 'Disable interactive prompts.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 36, HelpMessage = 'Disable interactive prompts.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 36, HelpMessage = 'Disable interactive prompts.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 36, HelpMessage = 'Disable interactive prompts.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 36, HelpMessage = 'Disable interactive prompts.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 36, HelpMessage = 'Disable interactive prompts.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 36, HelpMessage = 'Disable interactive prompts.',ParameterSetName = 'Moniker')]
        [Switch]$disableinteractivity,
		
		[Parameter( Mandatory = $false, Position = 37, HelpMessage = 'Set a proxy to use for this execution.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 37, HelpMessage = 'Set a proxy to use for this execution.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 37, HelpMessage = 'Set a proxy to use for this execution.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 37, HelpMessage = 'Set a proxy to use for this execution.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 37, HelpMessage = 'Set a proxy to use for this execution.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 37, HelpMessage = 'Set a proxy to use for this execution.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 37, HelpMessage = 'Set a proxy to use for this execution.',ParameterSetName = 'Proxy')]
		[Parameter( Mandatory = $false, Position = 37, HelpMessage = 'Set a proxy to use for this execution.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 37, HelpMessage = 'Set a proxy to use for this execution.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 37, HelpMessage = 'Set a proxy to use for this execution.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 37, HelpMessage = 'Set a proxy to use for this execution.',ParameterSetName = 'Moniker')]
        [String]$proxy,
		
		[Parameter( Mandatory = $false, Position = 38, HelpMessage = 'Disable the use of proxy for this execution.',ParameterSetName = 'AdminMode')]
		[Parameter( Mandatory = $false, Position = 38, HelpMessage = 'Disable the use of proxy for this execution.',ParameterSetName = 'UserMode')]
		[Parameter( Mandatory = $false, Position = 38, HelpMessage = 'Disable the use of proxy for this execution.',ParameterSetName = 'Action')]
		[Parameter( Mandatory = $false, Position = 38, HelpMessage = 'Disable the use of proxy for this execution.',ParameterSetName = 'Interactive')]
		[Parameter( Mandatory = $false, Position = 38, HelpMessage = 'Disable the use of proxy for this execution.',ParameterSetName = 'Silent')]
		[Parameter( Mandatory = $false, Position = 38, HelpMessage = 'Disable the use of proxy for this execution.',ParameterSetName = 'Override')]
		[Parameter( Mandatory = $false, Position = 38, HelpMessage = 'Disable the use of proxy for this execution.',ParameterSetName = 'Manifest')]
		[Parameter( Mandatory = $false, Position = 38, HelpMessage = 'Disable the use of proxy for this execution.',ParameterSetName = 'ID')]
		[Parameter( Mandatory = $false, Position = 38, HelpMessage = 'Disable the use of proxy for this execution.',ParameterSetName = 'Name')]
		[Parameter( Mandatory = $false, Position = 38, HelpMessage = 'Disable the use of proxy for this execution.',ParameterSetName = 'Moniker')]
        [Switch]$noproxy
		
    )

    Begin {
        ## Get the name of this function and write header
        [String]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
        Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
    }

    Process {
		Write-Verbose "PSBoundParameters: $($PSBoundParameters.Keys)"
		$argsWinGet = $null
		Switch ($scope) {
            'Any' {
                
            }
            'User' {
                $argsWinGet += " --scope user"
				Write-Verbose "Adding scope to argsWinGet: $($argsWinGet)"
            }
            'Machine' {
                $argsWinGet += " --scope machine"
				Write-Verbose "Adding scope to argsWinGet: $($argsWinGet)"
            }
            'UserOrUnknown' {
                
            }
            'SystemOrUnknown' {
                
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
            $argsWinGet += " --manifest $manifest"
			Write-Verbose "Adding wingetmanifest to argsWinGet: $($argsWinGet)"
        }
		If ($id) {
			Write-Verbose "IF id: $($id)"
            $argsWinGet += " --id $id"
			Write-Verbose "Adding id to argsWinGet: $($argsWinGet)"
        }
        If ($name) {
			Write-Verbose "IF name: $($name)"
            $argsWinGet += " --name $name"
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
            $argsWinGet += " --log $log"
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
            $argsWinGet += " --location $location"
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
            $argsWinGet += " --dependency-source"
			Write-Verbose "Adding dependencysource to argsWinGet: $($argsWinGet)"
        }
		If (($($PSBoundParameters.Keys) -Match 'acceptpackageagreements')-OR($Action -NE 'Uninstall')){
			Write-Verbose "PSBoundParameters -Match acceptpackageagreements)"
			If ($acceptpackageagreements) {
				Write-Verbose "IF acceptpackageagreements: $($acceptpackageagreements)"
				$argsWinGet += " --accept-package-agreements"
				Write-Verbose "Adding acceptpackageagreements to argsWinGet: $($argsWinGet)"
			}
		}
        If ($noupgrade) {
			Write-Verbose "IF noupgrade: $($noupgrade)"
            $argsWinGet += " --no-upgrade"
			Write-Verbose "Adding noupgrade to argsWinGet: $($argsWinGet)"
        }
        If ($header) {
			Write-Verbose "IF header: $($header)"
            $argsWinGet += " --header $header"
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
            $argsWinGet += " --rename $rename"
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
		If ($wait) {
			Write-Verbose "IF wait: $($wait)"
            $argsWinGet += " --wait"
			Write-Verbose "Adding wait to argsWinGet: $($argsWinGet)"
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
		
		Write-Verbose "Final argsWinGet: $($argsWinGet)"
		Write-Log -Message "Final argsWinGet: $($argsWinGet)" -Source "Start-WinGetPackageFM"
		Write-Verbose "Action: $($Action)"
		Write-Log -Message "UserMode: $($Mode)" -Source "Start-WinGetPackageFM"
		$wingetpath = Resolve-WingetPath -UserMode $UserMode
		Write-Log -Message "Installing $($id) via Winget" -Source "Start-WinGetPackageFM"
		Execute-Process -Path "$wingetpath\winget.exe" -Parameters "$Action $argsWinGet" -WindowStyle 'Hidden'
		Write-Log -Message "Done installing $($id) via Winget" -Source "Start-WinGetPackageFM"
		
	}
		
    End {
        Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
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
        ## Get the name of this function and write header
        [String]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
        Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -CmdletBoundParameters $PSBoundParameters -Header
    }

    Process {
		Write-Log -Message "Starting check of WinGet" -Source 'Resolve-WingetPath' -LogType 'CMTrace'
		If($UserMode -eq "Admin"){
			$ResolveWingetPath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_1.21*_x64__8wekyb3d8bbwe"
			if($ResolveWingetPath -EQ $null){
				$ResolveWingetPath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe"
			}
			if($ResolveWingetPath){
				$WingetPath = $ResolveWingetPath[-1].Path
			}
		}
		If($UserMode -eq "User"){
			$ResolveWingetPath = Resolve-Path "$env:LOCALAPPDATA\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller*\"
			if($ResolveWingetPath -EQ $null){
				$ResolveWingetPath = Resolve-Path "$env:LOCALAPPDATA\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\"
			}
			if($ResolveWingetPath){
				$WingetPath = $ResolveWingetPath[-1].Path
			}
		}
		if($ResolveWingetPath -EQ $null){
			Write-Log -Message "ERROR, path for winget not found" -Source 'Resolve-WingetPath' -LogType 'CMTrace'
			Throw "Path for winget not found"
			Break
		}
		Write-Log -Message "Winget path: $($WingetPath)" -Source 'Resolve-WingetPath' -LogType 'CMTrace'
		return $WingetPath
	}
		
    End {
        Write-FunctionHeaderOrFooter -CmdletName ${CmdletName} -Footer
    }
}
#endregion

##*===============================================
##* END FUNCTION LISTINGS
##*===============================================

##*===============================================
##* SCRIPT BODY
##*===============================================

If ($scriptParentPath) {
    Write-Log -Message "Script [$($MyInvocation.MyCommand.Definition)] dot-source invoked by [$(((Get-Variable -Name MyInvocation).Value).ScriptName)]" -Source $appDeployToolkitExtName
}
Else {
    Write-Log -Message "Script [$($MyInvocation.MyCommand.Definition)] invoked directly" -Source $appDeployToolkitExtName
}

## Evaluate non-default parameters passed to the scripts
If ($appDeployExtScriptParameters) {
    [String]$appDeployExtScriptParameters = ($appDeployExtScriptParameters.GetEnumerator() | ForEach-Object { & $ResolveParameters $_ }) -join ' '
}

##*===============================================
##* END SCRIPT BODY
##*===============================================
