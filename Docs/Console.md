# WingetFW Console

[Back to README](../README.md)

A window for admins that finds a winget package and builds the WingetFW install command, uninstall command
and detection script for an Intune app. It changes nothing in Intune or on the device.

Version 0.1.0 (phase CON-1): search, details, commands, detection script. Publishing to Intune comes in a later version.

## REQUIREMENTS
- Windows with PowerShell 7.4 or later.
- The modules `Microsoft.WinGet.Client` (search) and `powershell-yaml` (manifest details):
  ```
  Install-PSResource -Name Microsoft.WinGet.Client, powershell-yaml -Scope CurrentUser
  ```
- Internet access to GitHub (`raw.githubusercontent.com`) for the manifest details of the `winget` source.
- Run it from the repository folder. It reads `Toolkit\WinGetFW<version>` (the newest one), `Toolkit\Detection` and `Tools\WingetFW-ParameterMap.psd1`.

## START
```
pwsh -File .\Console\Start-WingetFWConsole.ps1
```

## SEARCH AND BUILD
1. Type a name, ID, moniker or tag, select the source and click **Search**.
2. Select a package. The versions and the manifest details are shown.
   - Source `winget`: the manifest from GitHub winget-pkgs, with all installers (architecture, installer type, scope, locale, silent switch, product code).
   - Other sources (`msstore`, REST sources): the text of `winget show`.
3. Select an installer to use its scope, architecture and installer type. An installer with scope `user` sets **Mode** to User (Intune install behavior User).
4. Set the other options. **Other options** takes any other WingetFW parameter, for example `-skipdependencies -locale 'en-US'`.
5. Copy the install and uninstall commands.
6. Pick the detection type and copy or save the detection script.

## HOW THE COMMANDS ARE BUILT
- Values are written in single quotes, see [command line quoting](Getting-Started.md#command-line-quoting).
- The commands are checked with the same [option rules](Parameters.md#option-rules) as WingetFW. A broken rule is shown as an error with the text WingetFW would write to its log (exit code 60001 or 69001).
- The uninstall command uses the same package, mode, scope and options. It leaves out `-Action`, `-ForceRepair`, `-version` (an upgraded app would not be found any more) and the options winget uninstall does not support. The left-out options are listed.
- Double quotes in a value give a warning: `Invoke-AppDeployToolkit.exe` does not pass them on as typed.

## DETECTION SCRIPT
| Type | Template | Use |
|---|---|---|
| winget list | newest `Toolkit\Detection\wingetv<version>.ps1` | Admin and User mode. Detected when `winget list --id <ID> --exact` finds the package. |
| Uninstall registry key | newest `Toolkit\Detection\registryversionregexv.<version>.ps1` | Admin mode only (reads HKLM). Detected when the display name matches (wildcards allowed) and the version is the same or newer. `0` = any version. |

Only the `$app` line (or the `$AppName` and `$AppVersion` lines) of the template is changed, so `Tools\Update-WingetFWIntuneApps.ps1` recognizes the script version.

## TESTS
- `Tests\Unit\WingetFW.Console.Tests.ps1`: builder, option rules, quoting, detection scripts, manifest data.
- The builder is also checked against every command of the last VM test run (`Tests\results\WingetFW-TestResults.json`): commands that passed on the VM are accepted, the validation tests (V01-V10, N01) are rejected with the same message as the WingetFW log.
