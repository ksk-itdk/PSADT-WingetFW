---
<sup>**IMPORTANT:-** This has been developed as a starting point or foundation and is not necessarily considered "complete". It is being made available to allow learning, development, and knowledge-sharing amongst communities.<br>
</sup>

---

## What is PSADT-WingetFW

PSADT-WingetFW is a framework for using Winget with PSADT without having to create a script for each application.

## EXAMPLES
### EXAMPLE 1
```
Deploy-Application.exe -DeploymentType 'Install' -id 'Postman.Postman' -Mode 'User'
```

![alt text](https://github.com/kriskristensen3/PSADT-WingetFW/blob/main/Images/exampleInstallCommand03.png?raw=true)
### EXAMPLE 2
```
ServiceUI.exe -process:explorer.exe Deploy-Application.exe -DeploymentType 'Install' -id 'Neovim.Neovim' -Scope 'machine'
```
![alt text](https://github.com/kriskristensen3/PSADT-WingetFW/blob/main/Images/exampleInstallCommand02.png?raw=true)
### EXAMPLE 3
User mode with no error dialog (recommended for Intune install behavior User).
```
Deploy-Application.exe -DeploymentType 'Install' -id 'Postman.Postman' -Mode 'User' -DeployMode 'NonInteractive'
```
### EXAMPLE 4
Upgrade to the latest version.
```
Deploy-Application.exe -DeploymentType 'Install' -Action 'upgrade' -id '7zip.7zip' -exact -silent
```
### EXAMPLE 5
Uninstall by product code. The GUID must be in single quotes.
```
Deploy-Application.exe -DeploymentType 'Uninstall' -productcode '{23170F69-40C1-2702-2604-000001000000}' -silent
```
### EXAMPLE 6
Install the packages in a winget export file.
```
Deploy-Application.exe -DeploymentType 'Install' -Action 'import' -importfile 'C:\Temp\my apps.json' -ignoreunavailable
```
### EXAMPLE 7
Repair with winget repair, or with uninstall and install again (-ForceRepair).
```
Deploy-Application.exe -DeploymentType 'Repair' -id '7zip.7zip' -exact -silent
Deploy-Application.exe -DeploymentType 'Repair' -ForceRepair -id '7zip.7zip' -exact -silent -scope 'Machine'
```

## COMMAND LINE QUOTING
`Deploy-Application.exe` (PSADT v3) removes double quotes and passes the arguments to `powershell.exe -Command`.
- A value in double quotes that contains spaces is split. `Deploy-Application.ps1` does not start, but the exit code is **0**.
- An unquoted `{GUID}` loses its braces.

Use **single quotes** for values with spaces or special characters, for example `-log 'C:\Logs\my app.log'` or `-productcode '{GUID}'`.

## ADMIN AND USER MODE
| Mode | Intune install behavior | winget used | Notes |
|---|---|---|---|
| Admin (default) | System | `C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe` (newest version) | Installs winget and the winget source if they are missing or older than the minimum version. |
| User | User | winget of the logged-on user | Only checks the winget version, does not install winget. |

User mode:
- Only works with packages that can install without admin rights: the manifest has `Scope: user`, or it is a portable package. Example: `Postman.Postman` works, `7zip.7zip` does not (`Scope: machine`, `ElevationRequirement: elevatesSelf`).
- Use `-DeployMode 'NonInteractive'`. With `Silent` or `Interactive`, an error shows a PSADT dialog and the script waits until it is closed or until `InstallationUI_Timeout` (6900 seconds) before it exits. This is longer than the default Intune install timeout.

## REPAIR AND FORCEREPAIR
- `-DeploymentType 'Repair'` runs `winget repair`. Not all packages support it. Example: the 7-Zip MSI returns `0x8A15007B` (repair failed).
- `-DeploymentType 'Repair' -ForceRepair` runs `winget uninstall` and then `winget install`. Options that uninstall does not support (for example `-custom`, `-allowreboot`, `-skipdependencies`) are skipped in the uninstall step and logged as a warning. The install step uses all options.
- `-ForceRepair` is ignored with Install and Uninstall.

## OPTION RULES
These are checked before winget runs. If a rule is broken, the script stops with exit code 60001 and the reason is written to the log.

Options that cannot be used together:
- `-wingetmanifest`, `-id`, `-name`, `-moniker` (use only one)
- `-interactive`, `-silent`, `-override` (use only one)
- `-proxy` and `-noproxy`
- `-purge` and `-preserve`

Other rules:
- `-header` requires `-source`.
- An option can only be used with the winget actions that support it. The log lists the allowed options. Examples:

| Option | Allowed with |
|---|---|
| `-importfile`, `-ignoreunavailable`, `-ignoreversions` | import |
| `-noupgrade` | install, import |
| `-rename`, `-dependencysource` | install |
| `-custom`, `-override`, `-location` | install, upgrade |
| `-productcode` | uninstall, repair |
| `-allversions`, `-preserve` | uninstall |
| `-purge` | uninstall, upgrade |
| `-includeunknown`, `-includepinned` | upgrade |

`--accept-package-agreements` is never sent with uninstall.

## WINGET ADMIN SETTINGS
Some options only work when a winget admin setting is enabled on the device (`winget settings --enable <setting>` as administrator):

| Option | winget admin setting |
|---|---|
| `-wingetmanifest` | `LocalManifestFiles` |
| `-ignoresecurityhash` | `InstallerHashOverride` |
| `-ignorelocalarchivemalwarescan` | `LocalArchiveMalwareScanOverride` |
| `-proxy` | `ProxyCommandLineOptions` |

## CONFIGURATION
`Toolkit\WinGetFW\AppDeployToolkit\AppDeployToolkitExtensionsConfig.xml`:

| Setting | Value in package | Description |
|---|---|---|
| `WingetFW_TlsCheck` | False | Admin mode: check `SecurityProtocol` before downloads and add TLS 1.2 if it is missing. |
| `WingetFW_VCRedistCheck` | False | Admin mode: install the VC++ 2015-2022 runtime (x64/x86) if it is missing. winget.exe run as SYSTEM fails with `0xC000007B` without it. |

If the file or a setting is missing, the check runs.

## EXIT CODES
| Exit code | Meaning |
|---|---|
| 0 | Success |
| 60001 | An option rule was broken (see [OPTION RULES](#option-rules)) or another error occurred. The reason is in the log. |
| 69001 | No package specified. Use `-id`, `-name`, `-moniker`, `-wingetmanifest`, `-productcode` or `-importfile`. |
| Other | The winget return code is passed through, for example `-1978335135` (`0x8A150061`, package already installed). See [winget return codes](https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md). |

## LOG FILE
```
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\<OverrideAPPName|id|name>_WingetFW_<version>_EN_01_PSAppDeployToolkit_<DeploymentType>.log
```
The log contains the WingetFW parameters, the final winget command line and the winget exit code. Use `-OverrideAPPName` to change the first part of the file name. Use `-log` for winget's own log file.

## TESTS
The test suite and the latest results are in [Tests/README.md](Tests/README.md) and [Tests/TEST-RESULTS.md](Tests/TEST-RESULTS.md).

## PARAMETERS
### -DeploymentType
The PSADT deployment type. Options: Install, Uninstall, Repair.
```
Type: String
Accepted values: Install, Uninstall, Repair
Required: False
Default value: Install
```

### -Mode
Run winget as SYSTEM (Admin) or as the logged-on user (User). See [ADMIN AND USER MODE](#admin-and-user-mode).
```
Type: String
Accepted values: Admin, User
Required: False
Default value: Admin
```

### -DeployMode
Standard PSADT parameter. Use NonInteractive with -Mode User, see [ADMIN AND USER MODE](#admin-and-user-mode).
```
Type: String
Accepted values: Interactive, Silent, NonInteractive
Required: False
Default value: Interactive
```

### -Action
The winget command to run. Options: install, uninstall, upgrade, import, repair.
```
Type: String
Accepted values: Install, Uninstall, upgrade, import, Repair
Required: False
Default value: $DeploymentType
```

### -wingetmanifest
Path to a local manifest folder or YAML file. Requires the winget admin setting LocalManifestFiles.
```
Type: String
Required: False
Default value: None
```

### -id
The ID from Winget
```
Type: String
Required: False
Default value: None
```

### -name
The name from Winget
```
Type: String
Required: False
Default value: None
```

### -moniker
The moniker from Winget
```
Type: String
Required: False
Default value: None
```

### -version
Specify an exact version to install. If not defined, the latest version in WinGet will be installed.
```
Type: String
Required: False
Default value: None
```

### -source
Restricts the search to the source name provided. Must be followed by the source name.
```
Type: String
Required: False
Default value: None
```

### -scope
Install scope. Options: Machine, User.
```
Type: String
Accepted values: Machine, User
Required: False
Default value: None
```

### -architecture
Select the architecture to install. Options: Default, X86, Arm, X64, Arm64.
```
Type: String
Accepted values: Default, X86, Arm, X64, Arm64
Required: False
Default value: None
```

### -installertype
Select the installer type to install. See supported installer types for WinGet client. Options: Default, Inno, Wix, Msi, Nullsoft, Zip, Msix, Exe, Burn, MSStore, Portable.
If not defined, the default installer type will be used. Note: the 7-Zip MSI is type Wix, not Msi.
```
Type: String
Accepted values: Default, Inno, Wix, Msi, Nullsoft, Zip, Msix, Exe, Burn, MSStore, Portable
Required: False
Default value: Default
```

### -exact
Uses the exact string in the query, including checking for case-sensitivity.
```
Type: Switch
Required: False
Default value: None
```

### -interactive
Runs the installer in interactive mode. Cannot be used with -silent or -override.
```
Type: Switch
Required: False
Default value: None
```

### -silent
Runs the installer in silent mode. Cannot be used with -interactive or -override.
```
Type: Switch
Required: False
Default value: None
```

### -locale
Specifies which locale to use (BCP47 format).
```
Type: String
Required: False
Default value: None
```

### -log
Directs the logging to a log file. You must provide a path to a file that you have the write rights to. Use single quotes if the path has spaces.
```
Type: String
Required: False
Default value: None
```

### -custom
Arguments to be passed on to the installer in addition to the defaults, like: '"/QN"'. Or '"REBOOT=ReallySuppress"'
'"INSTALL_ROOT=''C:\Program Files (x86)\JMeter''"'
```
Type: String
Required: False
Default value: None
```

### -override
A string that will be passed directly to the installer, like: '"/QN"'. Or '"/VERYSILENT /NOREBOOT /DIR=''C:\Program Files\nvm''"'
'"INSTALL_ROOT=''C:\Program Files (x86)\JMeter''"'
Cannot be used with -interactive or -silent.
```
Type: String
Required: False
Default value: None
```

### -location
Location to install to (if supported).
```
Type: String
Required: False
Default value: None
```

### -ignoresecurityhash
Ignore the installer hash check failure. Requires the winget admin setting InstallerHashOverride.
```
Type: Switch
Required: False
Default value: None
```

### -allowreboot
Allows a reboot if applicable.
```
Type: Switch
Required: False
Default value: None
```

### -skipdependencies
Skips processing package dependencies and Windows features.
```
Type: Switch
Required: False
Default value: None
```

### -ignorelocalarchivemalwarescan
Ignore the malware scan performed as part of installing an archive type package from local manifest. Requires the winget admin setting LocalArchiveMalwareScanOverride.
```
Type: Switch
Required: False
Default value: None
```

### -dependencysource
Find package dependencies using the specified source.
```
Type: String
Required: False
Default value: None
```

### -acceptpackageagreements
Used to accept the license agreement, and avoid the prompt. Not sent with uninstall.
```
Type: Switch
Required: False
Default value: True
```

### -noupgrade
Skips upgrade if an installed version already exists.
```
Type: Switch
Required: False
Default value: None
```

### -header
Optional Windows-Package-Manager REST source HTTP header. Requires -source. winget ignores the header for sources that are not REST sources.
```
Type: String
Required: False
Default value: None
```

### -authenticationmode
Specify authentication window preference.
```
Type: String
Accepted values: silent, silentPreferred, interactive
Required: False
Default value: None
```

### -authenticationaccount
Specify the account to be used for authentication.
```
Type: String
Required: False
Default value: None
```

### -acceptsourceagreements
Used to accept the source license agreement, and avoid the prompt.
```
Type: Switch
Required: False
Default value: True
```

### -rename
The value to rename the executable file (portable).
```
Type: String
Required: False
Default value: None
```

### -uninstallprevious
Uninstall the previous version of the package during upgrade.
```
Type: Switch
Required: False
Default value: None
```

### -force
Direct run the command and continue with non security related issues.
```
Type: Switch
Required: False
Default value: None
```

### -enableverbose
Used to override the logging setting and create a verbose log.
```
Type: Switch
Required: False
Default value: None
```

### -ignorewarnings
Suppresses warning outputs.
```
Type: Switch
Required: False
Default value: None
```

### -disableinteractivity
Disable interactive prompts.
```
Type: Switch
Required: False
Default value: None
```

### -proxy
Set a proxy to use for this execution. Requires the winget admin setting ProxyCommandLineOptions. Cannot be used with -noproxy.
```
Type: String
Required: False
Default value: None
```

### -noproxy
Disable the use of proxy for this execution. Cannot be used with -proxy.
```
Type: Switch
Required: False
Default value: None
```

### -importfile
JSON file describing the packages to install. Only with -Action import.
```
Type: String
Required: False
Default value: None
```

### -ignoreunavailable
Suppresses errors if a package in the import file is unavailable. Only with -Action import.
```
Type: Switch
Required: False
Default value: None
```

### -ignoreversions
Ignores the versions in the import file and installs the latest available version. Only with -Action import.
```
Type: Switch
Required: False
Default value: None
```

### -productcode
Filters using the product code. Uninstall and repair. Use single quotes around a {GUID}.
```
Type: String
Required: False
Default value: None
```

### -allversions
Uninstall all versions. Uninstall only.
```
Type: Switch
Required: False
Default value: None
```

### -purge
Deletes all files and directories in the package directory (portable). Uninstall and upgrade. Cannot be used with -preserve.
```
Type: Switch
Required: False
Default value: None
```

### -preserve
Retains all files and directories created by the package (portable). Uninstall only. Cannot be used with -purge.
```
Type: Switch
Required: False
Default value: None
```

### -includeunknown
Upgrade packages even if their current version cannot be determined. Upgrade only.
```
Type: Switch
Required: False
Default value: None
```

### -includepinned
Upgrade packages even if they have a non-blocking pin. Upgrade only.
```
Type: Switch
Required: False
Default value: None
```

### -ForceRepair
With -DeploymentType Repair: uninstall and install again instead of winget repair. Ignored with Install and Uninstall. See [REPAIR AND FORCEREPAIR](#repair-and-forcerepair).
```
Type: Switch
Required: False
Default value: None
```

### -OverrideAPPName
Will override ID or Name use for the UI and the log.
```
Type: String
Required: False
Default value: None
```
