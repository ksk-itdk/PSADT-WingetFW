---
<sup>**IMPORTANT:-** This has been developed as a starting point or foundation and is not necessarily considered "complete". It is being made available to allow learning, development, and knowledge-sharing amongst communities.<br>
</sup>

---

## What is PSADT-WingetFW

PSADT-WingetFW is framework for using Winget with PSADT without havning to create a script for each application
## EXAMPLES
### EXAMPLE 1
```
Deploy-Application.exe -DeploymentType "Install" -WingetID "Postman.Postman"
```

![alt text](https://github.com/kriskristensen3/PSADT-WingetFW/blob/main/Images/exampleInstallCommand01.png?raw=true)
### EXAMPLE 2
```
ServiceUI.exe -process:explorer.exe Deploy-Application.exe -DeploymentType "Install" -WingetID "Neovim.Neovim" -WingetScope '--Scope machine'
```
![alt text](https://github.com/kriskristensen3/PSADT-WingetFW/blob/main/Images/exampleInstallCommand02.png?raw=true)

## PARAMETERS
### -DeploymentType
The action to perform. Options: Install, Uninstall.
```
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Default value: Install
```

### -WingetID
Get the ID from Winget
```
Type: String
Parameter Sets: (All)
Aliases: Arguments

Required: True
Default value: None
```

### -Mode
The action to perform. Options: Admin, User.
```
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Default value: Admin
```

### -WingetScope
The action to perform. Options: machine, user.
```
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Default value: None
```

### -WingetOverride
Add parameters for winget, like: "/QN". Or "REBOOT=ReallySuppress"
```
Type: String
Parameter Sets: (All)
Aliases: Arguments

Required: False
Default value: None
```

### -WingetCM
Add parameters for winget, like: "--custom /QN". Or "--custom REBOOT=ReallySuppress"
```
Type: String
Parameter Sets: (All)
Aliases: Arguments

Required: False
Default value: None
```
