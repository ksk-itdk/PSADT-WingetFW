# WingetFW 5.0.0 - Parameters

[Back to README](../README.md)

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
Run winget as SYSTEM (Admin) or as the logged-on user (User). See [ADMIN AND USER MODE](Getting-Started.md#admin-and-user-mode).
```
Type: String
Accepted values: Admin, User
Required: False
Default value: Admin
```

### -DeployMode
Standard PSADT parameter. WingetFW shows no dialogs, so the default is fine in most cases.
```
Type: String
Accepted values: Auto, Interactive, NonInteractive, Silent
Required: False
Default value: Auto
```

### -SuppressRebootPassThru
Standard PSADT parameter. Returns 0 instead of a reboot exit code (3010, 1641) to Intune.
```
Type: Switch
Required: False
Default value: None
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
Without `-source`, install and upgrade use the `DefaultSource` setting if it is set. A source that is not in `AllowedSources` stops with 60001. See [Configuration](Configuration.md).
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
When none of -silent, -interactive and -override is used, WingetFW adds -silent unless the `DefaultSilent` setting is disabled. See [Configuration](Configuration.md).
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
Set a proxy to use for this execution. Requires the winget admin setting ProxyCommandLineOptions (WingetFW enables it in Admin mode). Cannot be used with -noproxy.
A `Proxy` policy beats -proxy and -noproxy; `Proxy` in the local key or config file is used when there is no -proxy or -noproxy. See [Configuration](Configuration.md).
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
With -DeploymentType Repair: uninstall and install again instead of winget repair. Ignored with Install and Uninstall. See [REPAIR AND FORCEREPAIR](Getting-Started.md#repair-and-forcerepair).
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
