# WingetFW 5 - Mod files

[Back to README](../README.md)

Mod files are PowerShell files with pre/post sections that run around winget, for one app or for all apps.
They replace a custom deployment script per app: the Intune app stays a normal WingetFW app, and the mod file
adds what the app needs, for example closing a process, setting a registry value or cleaning up after uninstall.

## FILES
| File | Used for |
|---|---|
| `<ScriptRoot>\<source>\<package id>.ps1` | One app, for example `winget\7zip.7zip.ps1` |
| `<ScriptRoot>\_WingetFW.ps1` | Every app (global mod) |
| `Toolkit\WinGetFW\Mods\_Template.ps1` | Template with all sections |

The [WingetFW Console](Console.md#mod-files-and-settings) creates mod files from the template, checks them like WingetFW, saves and signs them.

- The app mod is found by `-id` and the source: `-source`, else `DefaultSource`, else `winget`. Apps installed by `-name`, `-moniker`, `-wingetmanifest` or `-productcode` only use the global mod.
- `ScriptRoot` is a list of locations (see [SETTINGS](#settings)). The first location that has a file wins, for each file separately.
- Without settings, WingetFW uses the `Mods` folder in the package. You can put the mod files there and build the `.intunewin` with them.

## SECTIONS
| Action | Pre | During | Post (success) | Not (failure) |
|---|---|---|---|---|
| Install | `PreInstall` | `Install` | `PostInstall` | `NotInstalled` |
| Uninstall | `PreUninstall` | `Uninstall` | `PostUninstall` | `NotUninstalled` |
| Repair (also `-ForceRepair`) | `PreRepair` | `Repair` | `PostRepair` | `NotRepaired` |
| Upgrade (`-Action upgrade`) | `PreUpgrade` | `Upgrade` | `PostUpgrade` | `NotUpgraded` |
| Import (global mod only) | `PreImport` | | `PostImport` | |

Order:
1. global Pre, app Pre
2. winget (with `-ForceRepair`: uninstall, then install)
3. app During, global During - after winget, before the result is checked
4. app Post or Not, global Post or Not

- A Pre section that returns `$false` skips the action: winget does not run and the exit code is **69002**.
- When winget fails, the Not sections run and the exit code is the winget exit code.
- An error in a section stops the deployment with exit code 60001.
- Sections only need to exist when you use them.

Inside a section:
- PSAppDeployToolkit functions work and write to the same log, for example `Write-ADTLogEntry`, `Show-ADTInstallationWelcome`, `Set-ADTRegistryKey`, `Remove-ADTFolder`.
- `$WingetFW` has `Action`, `Id`, `Source`, `UserMode`, `ForceRepair`, `Parameters` (the winget parameters) and, after winget, `ExitCode` and `Success`.
- In user mode (`-Mode 'User'`) the sections run as the user.

## $SETTINGS
The app mod can set options per action. The command line beats them, so one Intune app can still use something else.

```powershell
$Settings = @{
    Install = @{
        Custom           = 'REBOOT=ReallySuppress'
        Scope            = 'Machine'
        SkipDependencies = $true
    }
    Upgrade = @{ Override = '/S' }
}
```

| Key | Same as |
|---|---|
| `Override`, `Custom`, `Scope`, `Locale`, `Architecture`, `Source`, `SkipDependencies` | The command line options, with the same [option rules](Parameters.md#option-rules) |
| `DefaultSilent`, `DefaultSource`, `Proxy` | The [settings](Configuration.md#settings) of the same name, at level 3 (after policy and command line) |

`$Settings` in the global mod is not used. `-ForceRepair` uses `$Settings.Repair` for both steps; options uninstall does not support are skipped there.

## CONFLICTING APPS
Remove apps that conflict with the app in `PreInstall` of the app mod, for example an old MSI version that winget
does not know, or a product that can't be installed next to this one. PSAppDeployToolkit's `Uninstall-ADTApplication`
finds the app in Programs and Features and uses its uninstall string (`msiexec /x` for MSI):

```powershell
function PreInstall
{
    # By name; -ArgumentList replaces the uninstall arguments, for example for an EXE uninstaller that is not silent
    Uninstall-ADTApplication -Name 'Contoso Viewer*' -NameMatch Wildcard -ArgumentList '/S'

    # By MSI product code
    Uninstall-ADTApplication -ProductCode '{26A24AE4-039D-4CA4-87B4-2F64180451F0}'
}
```

- Nothing happens when the app is not installed.
- When the uninstall fails, the deployment stops with exit code 60001 before winget runs; the uninstaller's own exit code is in the log.

## RULES FOR A MOD FILE
WingetFW checks every file before it runs anything in it. A file that breaks a rule stops the deployment with exit code 60001:
- Only function definitions and one `$Settings = @{ ... }` at the top level. Any other code, a `param` block or `using` is refused.
- `$Settings` may only contain fixed values: text, numbers, `$true`/`$false`, `@( ... )` and `@{ ... }`.
- The file must be in a location listed in `AllowedScriptSources`.
- With `RequireSignedScripts`, the file must have a valid signature (checked every run, also for cached copies).

## SETTINGS
Set them by policy (ADMX, category WingetFW > Mod files), the local key or the config file, see [Configuration](Configuration.md).

| Setting | Default | Description |
|---|---|---|
| `ScriptRoot` | package `Mods` folder | Ordered list: local folder, UNC share (`\\fs01\WingetFW\Mods`) or Azure blob container URL with SAS (`https://contoso.blob.core.windows.net/mods?sv=...&sp=r&sig=...`). |
| `ScriptSyncMode` | `OnDemand` | `OnDemand`: fetch only the files for this app (SAS: read). `Mirror`: copy all `.ps1` files of each location to the cache first and remove files that are gone (SAS: read + list). |
| `UseCachedScriptsWhenOffline` | off | When a location can't be reached: use the cached copy (on) or stop with 60001 (off). |
| `AllowedScriptSources` | package folder, `C:\ProgramData\WingetFW\Scripts` | Path or URL prefixes every location must start with. A SAS in a URL is ignored. |
| `RequireSignedScripts` | `Off` | `Off`, `Signed` (valid signature from a trusted certificate) or `TrustedSigners` (and the certificate thumbprint must be in `TrustedSigners`). |
| `TrustedSigners` | | Certificate thumbprints for `TrustedSigners`. |

Cache: `C:\ProgramData\WingetFW\Cache` (SYSTEM and Administrators only) in admin mode, `%LOCALAPPDATA%\WingetFW\Cache` in user mode.

## SECURITY
- Mod files run as SYSTEM in admin mode. Only people who may run code as SYSTEM on your devices should be able to change them: use a share or container that only admins can write to, and `AllowedScriptSources`.
- The policy key can be read by every user, so a SAS in `ScriptRoot` is visible to users. Use a read-only SAS (read + list for Mirror) and signed mod files. WingetFW masks the SAS signature in its log.
- Signing: see [Signing mod files](Signing.md) for the certificate, the Intune profile and the settings.
- WDAC: WDAC script rules do not apply to mod files; turn on `RequireSignedScripts`, see [Signing mod files](Signing.md#wdac).

## EXAMPLE
`\\fs01\WingetFW\Mods\winget\7zip.7zip.ps1`:

```powershell
$Settings = @{
    Install = @{ Scope = 'Machine' }
}

function PreInstall
{
    Show-ADTInstallationWelcome -CloseProcesses @{ Name = '7zFM' } -Silent
}

function PostUninstall
{
    Remove-ADTFolder -Path "$env:ProgramFiles\7-Zip"
}
```
