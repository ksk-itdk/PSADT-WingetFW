# WingetFW 5 - Upgrading Intune apps

[Back to README](../README.md)

## UPGRADING INTUNE APPS
> **BETA:** `Tools\Update-WingetFWIntuneApps.ps1` is not fully tested yet. Use it at your own risk, run `-Apply` with `-WhatIf` first and test it on a single app before updating more apps.
`Tools\Update-WingetFWIntuneApps.ps1` updates existing WingetFW apps (3.x, 4.x and 5.x) in Intune to a new WingetFW package. It needs PowerShell 7.4 or later, the `Microsoft.Graph.Authentication` module and the permission `DeviceManagementApps.Read.All` (export) or `DeviceManagementApps.ReadWrite.All` (apply). It logs in with a popup, or with an app registration (`-TenantId`, `-ClientId`, `-ClientSecret`).
The [WingetFW Console](Console.md#inventory-and-upgrade) does the same in a window (tab **Inventory and upgrade**) with the same functions and the same CSV.

1. Export: finds all Win32 apps that run `Deploy-Application.exe` or `Invoke-AppDeployToolkit.exe` with a WingetFW package parameter and writes a CSV with the old and new command lines, the changes, warnings, errors and the detection script used. Nothing is changed in Intune.
   ```
   .\Update-WingetFWIntuneApps.ps1 -Export
   ```
2. Review the CSV. Set `Update` to `No` (or delete the row) for apps that must not be updated. Rows with errors are set to `No`. The new command lines can be edited.
3. Apply: uploads the new `.intunewin` (setup file `Invoke-AppDeployToolkit.exe`) as a new content version of each app, sets the new command lines and writes `WingetFW <version>` to the app notes. Assignments, app ID and detection rules are kept. Use `-WhatIf` first.
   ```
   .\Update-WingetFWIntuneApps.ps1 -Apply -CsvPath .\WingetFW-IntuneApps-<date>.csv -IntuneWinFile .\Invoke-AppDeployToolkit.intunewin -WhatIf
   ```

The conversion of old parameters is in `Tools\WingetFW-ParameterMap.psd1`, for example:

| Old | New |
|---|---|
| `Deploy-Application.exe` (3.x, 4.x) | `Invoke-AppDeployToolkit.exe` |
| `-AllowRebootPassThru` (3.x, 4.x) | removed (reboot exit codes are passed by default, see `-SuppressRebootPassThru`) |
| `ServiceUI.exe ...` before the exe | error: `ServiceUI.exe` is not in the 5.0.0 package |
| `-WingetID` (3.x) | `-id` |
| `-WingetOverride` (3.x) | `-override` |
| `-WingetScope '--scope machine'` (3.x) | `-scope 'Machine'` |
| `-WingetCM '--custom ... --version ...'` (3.x) | `-custom '...' -version '...'` |
| 3.x always used `--silent` | `-silent` (not with `-override`) |
| `-testverbose` (4.0.0 - 4.0.6) | `-enableverbose` |
| `-wait` (4.0.0 - 4.0.6) | removed |
| `-scope Any/UserOrUnknown/SystemOrUnknown` (4.0.0 - 4.0.6) | removed (was not passed to winget) |
| `-DeploymentType Repair` (before 4.0.7, always uninstall + install) | `-DeploymentType Repair -ForceRepair` |

Use `-ConvertCommandLine '<command line>'` to see the conversion of one command line without connecting to Intune.
