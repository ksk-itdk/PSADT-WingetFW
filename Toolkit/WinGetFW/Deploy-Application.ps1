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


[CmdletBinding(DefaultParameterSetName = 'AdminMode')]
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
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies if you need to install, uninstall, upgrade or import.',ParameterSetName = 'Moniker')]
	[ValidateSet('Install', 'Uninstall', 'upgrade', 'import')]
	[String]$Action = $DeploymentType,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Must be followed by the path to the manifest (YAML) file. You can use the manifest to run the install experience from a local YAML file.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Must be followed by the path to the manifest (YAML) file. You can use the manifest to run the install experience from a local YAML file.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Must be followed by the path to the manifest (YAML) file. You can use the manifest to run the install experience from a local YAML file.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Must be followed by the path to the manifest (YAML) file. You can use the manifest to run the install experience from a local YAML file.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Must be followed by the path to the manifest (YAML) file. You can use the manifest to run the install experience from a local YAML file.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Must be followed by the path to the manifest (YAML) file. You can use the manifest to run the install experience from a local YAML file.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Must be followed by the path to the manifest (YAML) file. You can use the manifest to run the install experience from a local YAML file.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Must be followed by the path to the manifest (YAML) file. You can use the manifest to run the install experience from a local YAML file.',ParameterSetName = 'Manifest')]
	[String]$wingetmanifest,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the install to the ID of the application.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the install to the ID of the application.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the install to the ID of the application.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the install to the ID of the application.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the install to the ID of the application.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the install to the ID of the application.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the install to the ID of the application.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the install to the ID of the application.',ParameterSetName = 'ID')]
	[String]$id,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the search to the name of the application.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the search to the name of the application.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the search to the name of the application.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the search to the name of the application.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the search to the name of the application.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the search to the name of the application.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the search to the name of the application.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the search to the name of the application.',ParameterSetName = 'Name')]
	[String]$name,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the search to the moniker listed for the application.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the search to the moniker listed for the application.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the search to the moniker listed for the application.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the search to the moniker listed for the application.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the search to the moniker listed for the application.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the search to the moniker listed for the application.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the search to the moniker listed for the application.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Limits the search to the moniker listed for the application.',ParameterSetName = 'Moniker')]
	[String]$moniker,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Enables you to specify an exact version to install. If not specified, latest will install the highest versioned application.',ParameterSetName = 'Moniker')]
	[String]$version,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Restricts the search to the source name provided. Must be followed by the source name.',ParameterSetName = 'Moniker')]
	[String]$source,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Allows you to specify if the installer should target user or machine scope. See known issues relating to package installation scope.',ParameterSetName = 'Moniker')]
	[ValidateSet('Any', 'User', 'Machine', 'UserOrUnknown', 'SystemOrUnknown')]
	[String]$scope,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Select the architecture to install.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Select the architecture to install.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Select the architecture to install.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Select the architecture to install.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Select the architecture to install.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Select the architecture to install.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Select the architecture to install.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Select the architecture to install.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Select the architecture to install.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Select the architecture to install.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Select the architecture to install.',ParameterSetName = 'Moniker')]
	[ValidateSet('Default', 'X86', 'Arm', 'X64', 'Arm64')]
	[String]$architecture,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Select the installer type to install. See supported installer types for WinGet client.',ParameterSetName = 'Moniker')]
	[ValidateSet('Default', 'Inno', 'Wix', 'Msi', 'Nullsoft', 'Zip', 'Msix', 'Exe', 'Burn', 'MSStore', 'Portable')]
	[String]$installertype,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Uses the exact string in the query, including checking for case-sensitivity. It will not use the default behavior of a substring.',ParameterSetName = 'Moniker')]
	[Switch]$exact,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Runs the installer in interactive mode. The default experience shows installer progress.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Runs the installer in interactive mode. The default experience shows installer progress.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Runs the installer in interactive mode. The default experience shows installer progress.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Runs the installer in interactive mode. The default experience shows installer progress.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Runs the installer in interactive mode. The default experience shows installer progress.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Runs the installer in interactive mode. The default experience shows installer progress.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Runs the installer in interactive mode. The default experience shows installer progress.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Runs the installer in interactive mode. The default experience shows installer progress.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Runs the installer in interactive mode. The default experience shows installer progress.',ParameterSetName = 'Moniker')]
	[Switch]$interactive,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Runs the installer in silent mode. This suppresses all UI. The default experience shows installer progress.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Runs the installer in silent mode. This suppresses all UI. The default experience shows installer progress.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Runs the installer in silent mode. This suppresses all UI. The default experience shows installer progress.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Runs the installer in silent mode. This suppresses all UI. The default experience shows installer progress.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Runs the installer in silent mode. This suppresses all UI. The default experience shows installer progress.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Runs the installer in silent mode. This suppresses all UI. The default experience shows installer progress.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Runs the installer in silent mode. This suppresses all UI. The default experience shows installer progress.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Runs the installer in silent mode. This suppresses all UI. The default experience shows installer progress.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Runs the installer in silent mode. This suppresses all UI. The default experience shows installer progress.',ParameterSetName = 'Moniker')]
	[Switch]$silent,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies which locale to use (BCP47 format).',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies which locale to use (BCP47 format).',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies which locale to use (BCP47 format).',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies which locale to use (BCP47 format).',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies which locale to use (BCP47 format).',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies which locale to use (BCP47 format).',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies which locale to use (BCP47 format).',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies which locale to use (BCP47 format).',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies which locale to use (BCP47 format).',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies which locale to use (BCP47 format).',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specifies which locale to use (BCP47 format).',ParameterSetName = 'Moniker')]
	[String]$locale,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Directs the logging to a log file. You must provide a path to a file that you have the write rights to.',ParameterSetName = 'Moniker')]
	[String]$log,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Arguments to be passed on to the installer in addition to the defaults.',ParameterSetName = 'Moniker')]
	[String]$custom,
	
	[Parameter( Mandatory = $false, HelpMessage = 'A string that will be passed directly to the installer.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'A string that will be passed directly to the installer.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'A string that will be passed directly to the installer.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'A string that will be passed directly to the installer.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'A string that will be passed directly to the installer.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'A string that will be passed directly to the installer.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'A string that will be passed directly to the installer.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'A string that will be passed directly to the installer.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'A string that will be passed directly to the installer.',ParameterSetName = 'Moniker')]
	[String]$override,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Location to install to (if supported).',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Location to install to (if supported).',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Location to install to (if supported).',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Location to install to (if supported).',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Location to install to (if supported).',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Location to install to (if supported).',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Location to install to (if supported).',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Location to install to (if supported).',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Location to install to (if supported).',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Location to install to (if supported).',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Location to install to (if supported).',ParameterSetName = 'Moniker')]
	[String]$location,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Ignore the installer hash check failure. Not recommended.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Ignore the installer hash check failure. Not recommended.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Ignore the installer hash check failure. Not recommended.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Ignore the installer hash check failure. Not recommended.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Ignore the installer hash check failure. Not recommended.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Ignore the installer hash check failure. Not recommended.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Ignore the installer hash check failure. Not recommended.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Ignore the installer hash check failure. Not recommended.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Ignore the installer hash check failure. Not recommended.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Ignore the installer hash check failure. Not recommended.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Ignore the installer hash check failure. Not recommended.',ParameterSetName = 'Moniker')]
	[Switch]$ignoresecurityhash,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Allows a reboot if applicable.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Allows a reboot if applicable.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Allows a reboot if applicable.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Allows a reboot if applicable.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Allows a reboot if applicable.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Allows a reboot if applicable.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Allows a reboot if applicable.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Allows a reboot if applicable.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Allows a reboot if applicable.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Allows a reboot if applicable.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Allows a reboot if applicable.',ParameterSetName = 'Moniker')]
	[Switch]$allowreboot,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Skips processing package dependencies and Windows features.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Skips processing package dependencies and Windows features.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Skips processing package dependencies and Windows features.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Skips processing package dependencies and Windows features.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Skips processing package dependencies and Windows features.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Skips processing package dependencies and Windows features.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Skips processing package dependencies and Windows features.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Skips processing package dependencies and Windows features.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Skips processing package dependencies and Windows features.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Skips processing package dependencies and Windows features.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Skips processing package dependencies and Windows features.',ParameterSetName = 'Moniker')]
	[Switch]$skipdependencies,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Ignore the malware scan performed as part of installing an archive type package from local manifest.',ParameterSetName = 'Moniker')]
	[Switch]$ignorelocalarchivemalwarescan,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Find package dependencies using the specified source.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Find package dependencies using the specified source.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Find package dependencies using the specified source.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Find package dependencies using the specified source.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Find package dependencies using the specified source.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Find package dependencies using the specified source.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Find package dependencies using the specified source.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Find package dependencies using the specified source.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Find package dependencies using the specified source.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Find package dependencies using the specified source.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Find package dependencies using the specified source.',ParameterSetName = 'Moniker')]
	[String]$dependencysource,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to accept the license agreement, and avoid the prompt.',ParameterSetName = 'Moniker')]
	[Switch]$acceptpackageagreements,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Skips upgrade if an installed version already exists.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Skips upgrade if an installed version already exists.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Skips upgrade if an installed version already exists.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Skips upgrade if an installed version already exists.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Skips upgrade if an installed version already exists.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Skips upgrade if an installed version already exists.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Skips upgrade if an installed version already exists.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Skips upgrade if an installed version already exists.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Skips upgrade if an installed version already exists.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Skips upgrade if an installed version already exists.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Skips upgrade if an installed version already exists.',ParameterSetName = 'Moniker')]
	[Switch]$noupgrade,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Optional Windows-Package-Manager REST source HTTP header.',ParameterSetName = 'Moniker')]
	[String]$header,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specify authentication window preference (silent, silentPreferred or interactive).',ParameterSetName = 'Moniker')]
	[ValidateSet('silent', 'silentPreferred', 'interactive')]
	[String]$authenticationmode,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Specify the account to be used for authentication.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specify the account to be used for authentication.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specify the account to be used for authentication.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specify the account to be used for authentication.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specify the account to be used for authentication.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specify the account to be used for authentication.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specify the account to be used for authentication.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specify the account to be used for authentication.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specify the account to be used for authentication.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specify the account to be used for authentication.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Specify the account to be used for authentication.',ParameterSetName = 'Moniker')]
	[String]$authenticationaccount,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to accept the source license agreement, and avoid the prompt.',ParameterSetName = 'Moniker')]
	[Switch]$acceptsourceagreements,
	
	[Parameter( Mandatory = $false, HelpMessage = 'The value to rename the executable file (portable).',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'The value to rename the executable file (portable).',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'The value to rename the executable file (portable).',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'The value to rename the executable file (portable).',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'The value to rename the executable file (portable).',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'The value to rename the executable file (portable).',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'The value to rename the executable file (portable).',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'The value to rename the executable file (portable).',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'The value to rename the executable file (portable).',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'The value to rename the executable file (portable).',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'The value to rename the executable file (portable).',ParameterSetName = 'Moniker')]
	[String]$rename,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Uninstall the previous version of the package during upgrade.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Uninstall the previous version of the package during upgrade.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Uninstall the previous version of the package during upgrade.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Uninstall the previous version of the package during upgrade.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Uninstall the previous version of the package during upgrade.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Uninstall the previous version of the package during upgrade.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Uninstall the previous version of the package during upgrade.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Uninstall the previous version of the package during upgrade.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Uninstall the previous version of the package during upgrade.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Uninstall the previous version of the package during upgrade.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Uninstall the previous version of the package during upgrade.',ParameterSetName = 'Moniker')]
	[Switch]$uninstallprevious,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Direct run the command and continue with non security related issues.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Direct run the command and continue with non security related issues.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Direct run the command and continue with non security related issues.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Direct run the command and continue with non security related issues.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Direct run the command and continue with non security related issues.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Direct run the command and continue with non security related issues.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Direct run the command and continue with non security related issues.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Direct run the command and continue with non security related issues.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Direct run the command and continue with non security related issues.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Direct run the command and continue with non security related issues.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Direct run the command and continue with non security related issues.',ParameterSetName = 'Moniker')]
	[Switch]$force,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Prompts the user to press any key before exiting.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Prompts the user to press any key before exiting.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Prompts the user to press any key before exiting.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Prompts the user to press any key before exiting.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Prompts the user to press any key before exiting.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Prompts the user to press any key before exiting.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Prompts the user to press any key before exiting.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Prompts the user to press any key before exiting.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Prompts the user to press any key before exiting.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Prompts the user to press any key before exiting.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Prompts the user to press any key before exiting.',ParameterSetName = 'Moniker')]
	[Switch]$wait,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Used to override the logging setting and create a verbose log.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to override the logging setting and create a verbose log.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to override the logging setting and create a verbose log.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to override the logging setting and create a verbose log.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to override the logging setting and create a verbose log.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to override the logging setting and create a verbose log.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to override the logging setting and create a verbose log.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to override the logging setting and create a verbose log.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to override the logging setting and create a verbose log.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to override the logging setting and create a verbose log.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Used to override the logging setting and create a verbose log.',ParameterSetName = 'Moniker')]
	[Switch]$testverbose,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Suppresses warning outputs.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Suppresses warning outputs.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Suppresses warning outputs.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Suppresses warning outputs.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Suppresses warning outputs.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Suppresses warning outputs.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Suppresses warning outputs.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Suppresses warning outputs.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Suppresses warning outputs.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Suppresses warning outputs.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Suppresses warning outputs.',ParameterSetName = 'Moniker')]
	[Switch]$ignorewarnings,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Disable interactive prompts.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Disable interactive prompts.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Disable interactive prompts.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Disable interactive prompts.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Disable interactive prompts.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Disable interactive prompts.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Disable interactive prompts.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Disable interactive prompts.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Disable interactive prompts.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Disable interactive prompts.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Disable interactive prompts.',ParameterSetName = 'Moniker')]
	[Switch]$disableinteractivity,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Set a proxy to use for this execution.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Set a proxy to use for this execution.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Set a proxy to use for this execution.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Set a proxy to use for this execution.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Set a proxy to use for this execution.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Set a proxy to use for this execution.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Set a proxy to use for this execution.',ParameterSetName = 'Proxy')]
	[Parameter( Mandatory = $false, HelpMessage = 'Set a proxy to use for this execution.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Set a proxy to use for this execution.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Set a proxy to use for this execution.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Set a proxy to use for this execution.',ParameterSetName = 'Moniker')]
	[String]$proxy,
	
	[Parameter( Mandatory = $false, HelpMessage = 'Disable the use of proxy for this execution.',ParameterSetName = 'AdminMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Disable the use of proxy for this execution.',ParameterSetName = 'UserMode')]
	[Parameter( Mandatory = $false, HelpMessage = 'Disable the use of proxy for this execution.',ParameterSetName = 'Action')]
	[Parameter( Mandatory = $false, HelpMessage = 'Disable the use of proxy for this execution.',ParameterSetName = 'Interactive')]
	[Parameter( Mandatory = $false, HelpMessage = 'Disable the use of proxy for this execution.',ParameterSetName = 'Silent')]
	[Parameter( Mandatory = $false, HelpMessage = 'Disable the use of proxy for this execution.',ParameterSetName = 'Override')]
	[Parameter( Mandatory = $false, HelpMessage = 'Disable the use of proxy for this execution.',ParameterSetName = 'Manifest')]
	[Parameter( Mandatory = $false, HelpMessage = 'Disable the use of proxy for this execution.',ParameterSetName = 'ID')]
	[Parameter( Mandatory = $false, HelpMessage = 'Disable the use of proxy for this execution.',ParameterSetName = 'Name')]
	[Parameter( Mandatory = $false, HelpMessage = 'Disable the use of proxy for this execution.',ParameterSetName = 'Moniker')]
	[Switch]$noproxy
	
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
    [String]$appVendor = "$id"
    [String]$appName = 'WingetFW'
    [String]$appVersion = '4.0.0'
    [String]$appArch = ''
    [String]$appLang = 'EN'
    [String]$appRevision = '01'
    [String]$appScriptVersion = '1.0.0'
    [String]$appScriptDate = '21/05/2025'
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
		'Any' {
			
		}
		'User' {
			$parWinGet.Add("scope", "user")
		}
		'Machine' {
			$parWinGet.Add("scope", "machine")
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
		$parWinGet.Add("manifest", $wingetmanifest)
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
	}
	If ($interactive) {
		$parWinGet.Add("interactive", $true)
	}
	If ($silent) {
		$parWinGet.Add("silent", $true)
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
		$parWinGet.Add("location", $location)
	}
	If ($ignoresecurityhash) {
		$parWinGet.Add("ignoresecurityhash", $true)
	}
	If ($allowreboot) {
		$parWinGet.Add("allowreboot", $true)
	}
	If ($skipdependencies) {
		$parWinGet.Add("skipdependencies", $true)
	}
	If ($ignorelocalarchivemalwarescan) {
		$parWinGet.Add("ignorelocalarchivemalwarescan", $true)
	}
	If ($dependencysource) {
		$parWinGet.Add("dependencysource", $true)
	}
	If ($acceptpackageagreements) {
		$parWinGet.Add("acceptpackageagreements", $true)
	}
	If ($noupgrade) {
		$parWinGet.Add("noupgrade", $true)
	}
	If ($header) {
		$parWinGet.Add("header", $header)
	}
	If ($authenticationaccount) {
		$parWinGet.Add("authenticationaccount", $authenticationaccount)
	}
	If ($acceptsourceagreements) {
		$parWinGet.Add("acceptsourceagreements", $true)
	}
	If ($rename) {
		$parWinGet.Add("rename", $rename)
	}
	If ($uninstallprevious) {
		$parWinGet.Add("uninstallprevious", $true)
	}
	If ($force) {
		$parWinGet.Add("force", $true)
	}
	If ($wait) {
		$parWinGet.Add("wait", $true)
	}
	If ($enableverbose) {
		$parWinGet.Add("enableverbose", $true)
	}
	If ($ignorewarnings) {
		$parWinGet.Add("ignorewarnings", $true)
	}
	If ($disableinteractivity) {
		$parWinGet.Add("disableinteractivity", $true)
	}
	If ($proxy) {
		$parWinGet.Add("proxy", $proxy)
	}
	If ($noproxy) {
		$parWinGet.Add("noproxy", $true)
	}
	Write-Log -Message "parWinGet $parWinGet" -Source 'parWinGet-Check' -LogType 'CMTrace'

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
		IF ($id){
				Write-Log -Message "Start-WinGetPackageFM -UserMode $($Mode) -Action $($Action) $($parWinGet)" -Source 'Start-WinGetPackageFM' -LogType 'CMTrace'
				Start-WinGetPackageFM -UserMode $Mode -Action $Action @parWinGet

		}Else{
			Write-Log -Message "Package $($WingetID) not available" -Source 'INSTALLATION' -LogType 'CMTrace'
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
		IF ($id){
			Write-Log -Message "Start-WinGetPackageFM -UserMode $($Mode) -Action $($Action) $($parWinGet)" -Source 'Start-WinGetPackageFM' -LogType 'CMTrace'
			Start-WinGetPackageFM -UserMode $Mode -Action $Action @parWinGet

		}Else{
			Write-Log -Message "Package $($WingetID) not available" -Source 'UNINSTALLATION' -LogType 'CMTrace'
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
		
        ## <Perform Installation tasks here>
		Write-Log -Message "Mode $Mode" -Source 'Mode' -LogType 'CMTrace'
		IF ($id){
				Write-Log -Message "Start-WinGetPackageFM -UserMode $($Mode) -Action $($Action) $($parWinGet)" -Source 'Start-WinGetPackageFM' -LogType 'CMTrace'
				Start-WinGetPackageFM -UserMode $Mode -Action $Action @parWinGet

		}Else{
			Write-Log -Message "Package $($WingetID) not available" -Source 'INSTALLATION' -LogType 'CMTrace'
		}
		
        ##*===============================================
        ##* REPAIR
        ##*===============================================
        [String]$installPhase = 'Repair'
		
        ## <Perform Repair tasks here>
		Write-Log -Message "Mode $Mode" -Source 'Mode' -LogType 'CMTrace'
		IF ($id){
			Write-Log -Message "Start-WinGetPackageFM -UserMode $($Mode) -Action uninstall $($parWinGet)" -Source 'Start-WinGetPackageFM' -LogType 'CMTrace'
			Start-WinGetPackageFM -UserMode $Mode -Action 'uninstall' @parWinGet
			Write-Log -Message "Start-WinGetPackageFM -UserMode $($Mode) -Action install $($parWinGet)" -Source 'Start-WinGetPackageFM' -LogType 'CMTrace'
			Start-WinGetPackageFM -UserMode $Mode -Action 'install' @parWinGet

		}Else{
			Write-Log -Message "Package $($WingetID) not available" -Source 'UNINSTALLATION' -LogType 'CMTrace'
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
