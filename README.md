---
<sup>**IMPORTANT:-** This has been developed as a starting point or foundation and is not necessarily considered "complete". It is being made available to allow learning, development, and knowledge-sharing amongst communities.<br>
</sup>

---

## What is PSADT-WingetFW

PSADT-WingetFW is framework for using Winget with PSADT without havning to create a script for each application
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

## PARAMETERS
### -DeploymentType
The action to perform. Options: Install, Uninstall, Repair.
```
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Default value: Install
```

### -Mode
The action to perform. Options: Admin, User.
```
Type: String
Parameter Sets: (Admin, User)
Aliases:

Required: False
Default value: Admin
```

### -UserMode
The action to perform. Options: Admin, User.
```
Type: String
Parameter Sets: (Admin, User)
Aliases:

Required: False
Default value: $Mode
```

### -Action
The action to perform. Options: install, uninstall, upgrade or import.
```
Type: String
Parameter Sets: (install, uninstall, upgrade, import)
Aliases:

Required: False
Default value: $DeploymentType
```

### -id
The ID from Winget
```
Type: String
Parameter Sets: (All)
Aliases: Arguments

Required: False
Default value: None
```

### -name
The name from Winget
```
Type: String
Parameter Sets: (All)
Aliases: Arguments

Required: False
Default value: None
```

### -moniker
The moniker from Winget
```
Type: String
Parameter Sets: (All)
Aliases: Arguments

Required: False
Default value: None
```

### -version
Specify an exact version to install. If not defind the lastest version in WinGet will be installed
```
Type: String
Parameter Sets: (All)
Aliases: Arguments

Required: False
Default value: None
```

### -source
Restricts the search to the source name provided. Must be followed by the source name.
```
Type: String
Parameter Sets: (All)
Aliases: Arguments

Required: False
Default value: None
```

### -scope
The action to perform. Options: machine, user.
```
Type: String
Parameter Sets: (machine, user)
Aliases:

Required: False
Default value: None
```

### -architecture
Select the architecture to install. Options: Default, X86, Arm, X64, Arm64.
```
Type: String
Parameter Sets: (Default, X86, Arm, X64, Arm64)
Aliases:

Required: False
Default value: None
```

### -installertype
Select the installer type to install. See supported installer types for WinGet client. Options: Default, Inno, Wix, Msi, Nullsoft, Zip, Msix, Exe, Burn, MSStore, Portable.
If not defind the default installer types will be used
```
Type: String
Parameter Sets: (Default, Inno, Wix, Msi, Nullsoft, Zip, Msix, Exe, Burn, MSStore, Portable)
Aliases:

Required: False
Default value: Default
```

### -exact
Uses the exact string in the query, including checking for case-sensitivity.
```
Type: Switch
Aliases: Arguments

Required: False
Default value: None
```

### -interactive
Runs the installer in interactive mode.
```
Type: Switch
Aliases: Arguments

Required: False
Default value: None
```

### -silent
Runs the installer in silent mode.
```
Type: Switch
Aliases: Arguments

Required: False
Default value: None
```

### -locale
Specifies which locale to use (BCP47 format).
```
Type: String
Parameter Sets: (All)
Aliases: Arguments

Required: False
Default value: None
```

### -log
Directs the logging to a log file. You must provide a path to a file that you have the write rights to.
```
Type: String
Parameter Sets: (All)
Aliases: Arguments

Required: False
Default value: None
```

### -custom
Arguments to be passed on to the installer in addition to the defaults, like: '"/QN"'. Or '"REBOOT=ReallySuppress"'
```
Type: String
Parameter Sets: (All)
Aliases: Arguments

Required: False
Default value: None
```

### -override
A string that will be passed directly to the installer, like: '"/QN"'. Or '"/VERYSILENT /NOREBOOT /DIR=''C:\Program Files\nvm''"'
```
Type: String
Parameter Sets: (All)
Aliases: Arguments

Required: False
Default value: None
```

### -location
Location to install to (if supported).
```
Type: String
Parameter Sets: (All)
Aliases: Arguments

Required: False
Default value: None
```

### -ignoresecurityhash
Ignore the installer hash check failure.
```
Type: Switch
Aliases: Arguments

Required: False
Default value: None
```

### -allowreboot
Allows a reboot if applicable.
```
Type: Switch
Aliases: Arguments

Required: False
Default value: None
```

### -skipdependencies
Skips processing package dependencies and Windows features.
```
Type: Switch
Aliases: Arguments

Required: False
Default value: None
```

### -ignorelocalarchivemalwarescan
Ignore the malware scan performed as part of installing an archive type package from local manifest.
```
Type: Switch
Aliases: Arguments

Required: False
Default value: None
```

### -dependencysource
Find package dependencies using the specified source.
```
Type: String
Parameter Sets: (All)
Aliases: Arguments

Required: False
Default value: None
```

### -acceptpackageagreements
Used to accept the license agreement, and avoid the prompt.
```
Type: Switch
Aliases: Arguments

Required: False
Default value: True
```

### -noupgrade
Skips upgrade if an installed version already exists.
```
Type: Switch
Aliases: Arguments

Required: False
Default value: None
```

### -header
Optional Windows-Package-Manager REST source HTTP header.
```
Type: String
Parameter Sets: (All)
Aliases: Arguments

Required: False
Default value: None
```

### -authenticationmode
Specify authentication window preference.
```
Type: String
Parameter Sets: ('silent', 'silentPreferred', 'interactive')
Aliases: Arguments

Required: False
Default value: None
```

### -authenticationaccount
Specify the account to be used for authentication.
```
Type: String
Parameter Sets: (All)
Aliases: Arguments

Required: False
Default value: None
```

### -acceptsourceagreements
Used to accept the source license agreement, and avoid the prompt.
```
Type: Switch
Aliases: Arguments

Required: False
Default value: True
```

### -rename
The value to rename the executable file (portable).
```
Type: String
Parameter Sets: (All)
Aliases: Arguments

Required: False
Default value: None
```

### -uninstallprevious
Uninstall the previous version of the package during upgrade.
```
Type: Switch
Aliases: Arguments

Required: False
Default value: None
```

### -force
Prompts the user to press any key before exiting.
```
Type: Switch
Aliases: Arguments

Required: False
Default value: None
```

### -wait
Prompts the user to press any key before exiting.
```
Type: Switch
Aliases: Arguments

Required: False
Default value: None
```

### -enableverbose
Used to override the logging setting and create a verbose log.
```
Type: Switch
Aliases: Arguments

Required: False
Default value: None
```

### -ignorewarnings
Suppresses warning outputs.
```
Type: Switch
Aliases: Arguments

Required: False
Default value: None
```

### -disableinteractivity
Disable interactive prompts.
```
Type: Switch
Aliases: Arguments

Required: False
Default value: None
```

### -proxy
Set a proxy to use for this execution.
```
Type: String
Parameter Sets: (All)
Aliases: Arguments

Required: False
Default value: None
```

### -noproxy
Disable the use of proxy for this execution.
```
Type: Switch
Aliases: Arguments

Required: False
Default value: None
```