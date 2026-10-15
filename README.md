---
<sup>**IMPORTANT:-** This has been developed as a starting point or foundation and is not necessarily considered "complete". It is being made available to allow learning, development, and knowledge-sharing amongst communities.<br>
</sup>

---

## What is PSADT-WingetFW

PSADT-WingetFW is a framework for using Winget with PSADT without having to create a script for each application.

This README is for **WingetFW 5.0.0** (PSAppDeployToolkit 4.1.8, `Toolkit\WinGetFW5.0.0`, `Invoke-AppDeployToolkit.exe`). Older versions:
- [README-4.0.8.md](README-4.0.8.md): WingetFW 4.0.8 (PSAppDeployToolkit 3.9.3, `Toolkit\WinGetFW`, `Deploy-Application.exe`)
- [README-3.0.2.md](README-3.0.2.md): WingetFW 3.0.2

## Quick start
1. Create the `.intunewin` from the `Toolkit\WinGetFW5.0.0` folder with `Invoke-AppDeployToolkit.exe` as the setup file.
2. Create a Win32 app in Intune with the package. Example install and uninstall commands (install behavior System):
   ```
   Invoke-AppDeployToolkit.exe -DeploymentType 'Install' -id '7zip.7zip' -exact -silent -scope 'Machine'
   Invoke-AppDeployToolkit.exe -DeploymentType 'Uninstall' -id '7zip.7zip' -exact -silent
   ```
   For install behavior User, add `-Mode 'User'`.
3. Use a detection script from `Toolkit\Detection` (the newest `wingetv` or `registryversionregex` version).
4. Put values with spaces and `{GUID}` values in **single quotes**, see [command line quoting](Docs/Getting-Started.md#command-line-quoting).

## Documentation
| Topic | Content |
|---|---|
| [Getting started](Docs/Getting-Started.md) | Package content, examples, command line quoting, admin and user mode, repair and ForceRepair |
| [Parameters](Docs/Parameters.md) | All parameters, option rules, winget admin settings |
| [Configuration](Docs/Configuration.md) | WingetFW settings |
| [Exit codes and logs](Docs/Exit-Codes-and-Logs.md) | Exit codes, log files |
| [Upgrading Intune apps](Docs/Upgrading-Intune-Apps.md) | `Tools\Update-WingetFWIntuneApps.ps1` (beta) |
| [Tests](Tests/README.md) | Test suite. Latest run of WingetFW 5.0.0: 39 of 39 tests passed ([results](Tests/TEST-RESULTS.md)) |
| [Changelog](CHANGELOG.txt) | Changes per version |
| [Contributing](CONTRIBUTING.md) | Notes for changing the code |
| [Design](Docs/Design/Phases.md) | Specs and phase plan for WingetFW, WingetFW Console and WingetFW-Update |
