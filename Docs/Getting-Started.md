# WingetFW 5 - Getting started

[Back to README](../README.md)

## PACKAGE
Create the `.intunewin` from the `Toolkit\WinGetFW` folder with `Invoke-AppDeployToolkit.exe` as the setup file.

| Path | Content |
|---|---|
| `Invoke-AppDeployToolkit.exe` / `.ps1` | Setup file and deployment script with the WingetFW parameters |
| `PSAppDeployToolkit.Extensions\` | WingetFW functions (`Install-WinGetFM`, `Get-WinGetVersionFM`, `Start-WinGetPackageFM`, `Resolve-WingetPath`) |
| `PSAppDeployToolkit.Extensions\Config\WingetFW.psd1` | WingetFW settings, see [Configuration](Configuration.md) |
| `PSAppDeployToolkit.Extensions\WingetFW.Core\` | Shared module: settings, logging, event log, state files, mod files (copy of `Source\WingetFW.Core`) |
| `Mods\` | Default location for [mod files](Mods.md); `_Template.ps1` is the template |
| `Config\config.psd1`, `Assets\` | PSAppDeployToolkit settings, logo and banner |
| `PSAppDeployToolkit\` | PSAppDeployToolkit 4.1.8 module (do not change) |

## EXAMPLES
### EXAMPLE 1
User mode (Intune install behavior User).
```
Invoke-AppDeployToolkit.exe -DeploymentType 'Install' -id 'Postman.Postman' -Mode 'User'
```

![alt text](https://github.com/kriskristensen3/PSADT-WingetFW/blob/main/Images/exampleInstallCommand03.png?raw=true)
<sup>The screenshots show the 4.x command line with `Deploy-Application.exe`.</sup>
### EXAMPLE 2
Machine scope (Intune install behavior System).
```
Invoke-AppDeployToolkit.exe -DeploymentType 'Install' -id 'Neovim.Neovim' -scope 'Machine'
```
![alt text](https://github.com/kriskristensen3/PSADT-WingetFW/blob/main/Images/exampleInstallCommand02.png?raw=true)
### EXAMPLE 3
Uninstall.
```
Invoke-AppDeployToolkit.exe -DeploymentType 'Uninstall' -id 'Postman.Postman' -Mode 'User'
```
### EXAMPLE 4
Upgrade to the latest version.
```
Invoke-AppDeployToolkit.exe -DeploymentType 'Install' -Action 'upgrade' -id '7zip.7zip' -exact -silent
```
### EXAMPLE 5
Uninstall by product code. The GUID must be in single quotes.
```
Invoke-AppDeployToolkit.exe -DeploymentType 'Uninstall' -productcode '{23170F69-40C1-2702-2604-000001000000}' -silent
```
### EXAMPLE 6
Install the packages in a winget export file.
```
Invoke-AppDeployToolkit.exe -DeploymentType 'Install' -Action 'import' -importfile 'C:\Temp\my apps.json' -ignoreunavailable
```
### EXAMPLE 7
Repair with winget repair, or with uninstall and install again (-ForceRepair).
```
Invoke-AppDeployToolkit.exe -DeploymentType 'Repair' -id '7zip.7zip' -exact -silent
Invoke-AppDeployToolkit.exe -DeploymentType 'Repair' -ForceRepair -id '7zip.7zip' -exact -silent -scope 'Machine'
```

## COMMAND LINE QUOTING
`Invoke-AppDeployToolkit.exe` passes the arguments to `powershell.exe -Command "try { & 'Invoke-AppDeployToolkit.ps1' <arguments> } ..."`.
- A value in double quotes that contains spaces breaks the command: `Invoke-AppDeployToolkit.ps1` does not start and the exit code is **1**.
- An unquoted `{GUID}` loses its braces.

Use **single quotes** for values with spaces or special characters, for example `-log 'C:\Logs\my app.log'` or `-productcode '{GUID}'`.

## ADMIN AND USER MODE
| Mode | Intune install behavior | winget used | Notes |
|---|---|---|---|
| Admin (default) | System | `C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe` (newest version) | Installs winget and the winget source if they are missing or older than the minimum version. |
| User | User | winget of the logged-on user | Only checks the winget version, does not install winget. If winget is not found (for example right after the user's first logon), it requests the App Installer registration and retries for up to about 20 seconds. |

User mode only works with packages that can install without admin rights: the manifest has `Scope: user`, or it is a portable package. Example: `Postman.Postman` works, `7zip.7zip` does not (`Scope: machine`, `ElevationRequirement: elevatesSelf`).

An error does not show a dialog in 5.0.0, so `-DeployMode 'NonInteractive'` is no longer needed in user mode.

## REPAIR AND FORCEREPAIR
- `-DeploymentType 'Repair'` runs `winget repair`. Not all packages support it. Example: the 7-Zip MSI returns `0x8A15007B` (repair failed).
- `-DeploymentType 'Repair' -ForceRepair` runs `winget uninstall` and then `winget install`. Options that uninstall does not support (for example `-custom`, `-allowreboot`, `-skipdependencies`) are skipped in the uninstall step and logged as a warning. The install step uses all options.
- `-ForceRepair` is ignored with Install and Uninstall.
