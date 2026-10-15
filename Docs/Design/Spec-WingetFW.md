# WingetFW - Project spec

> Status: draft. Baseline: WingetFW 5.0.0 (PSAppDeployToolkit 4.1.8).
> Related specs: [WingetFW Console](Spec-WingetFW-Console.md), [WingetFW-Update](Spec-WingetFW-Update.md).
> Phase plan for all three: [Phases](Phases.md).

## 1. Purpose

WingetFW installs, uninstalls, upgrades, repairs and imports winget packages through PSAppDeployToolkit, so an
Intune or ConfigMgr app needs no script of its own. This spec covers the next version: shared settings
from policy, pre/post scripts ("mods") per app, source selection and conflicting-app handling.

WingetFW works on its own. WingetFW Console and WingetFW-Update are optional and reuse the same
settings, mods and state.

## 2. Baseline (5.0.0, done)

- PSAppDeployToolkit 4.1.8, setup file `Invoke-AppDeployToolkit.exe`.
- WingetFW functions in the `PSAppDeployToolkit.Extensions` module: `Install-WinGetFM`,
  `Get-WinGetVersionFM`, `Start-WinGetPackageFM`, `Resolve-WingetPath`.
- Admin mode (SYSTEM) and User mode, option rules per winget action (60001), no package (69001),
  winget exit codes passed through, settings in `PSAppDeployToolkit.Extensions\Config\WingetFW.psd1`.
- Test suite on a sandbox VM: 39/39.

## 3. Shared core (WingetFW.Core)

Functions used by WingetFW, WingetFW Console and WingetFW-Update. Built first, in this repo.

| Area | Content |
|---|---|
| Settings reader | Reads every setting in the order of section 4 and logs the value and where it came from. |
| winget | `Resolve-WingetPath`, version check, source handling. |
| Mods | Find, download, check and run mod files (section 6). |
| State | Read and write the state files (section 9). |
| Logging | CMTrace log through PSADT, Windows event log channel `WingetFW`. |

## 4. Settings and order

One value is taken from the first level that has it:

1. **Policy** - `HKLM\SOFTWARE\Policies\WingetFW`, written by Intune (imported ADMX / OMA-URI) or by GPO.
   One ADMX file serves both. Configure a device from Intune *or* GPO, not both: if both write the same
   value, the last write wins (GPO re-applies every 90 minutes).
2. **Command line** - the parameters of the Intune/ConfigMgr install command.
3. **Mod file** - `$Settings` in the app's mod file (section 6).
4. **Local key** - `HKLM\SOFTWARE\WingetFW`, for example set by a script or a remediation. Not enforced.
5. **Config file** - `PSAppDeployToolkit.Extensions\Config\WingetFW.psd1` in the package.
6. **Built-in default.**

The command line beats the mod file so a single Intune app can deviate from the app's normal settings.
Policy beats everything, so an admin can force a value centrally.

### 4.1 Device settings

| Setting | Type | Default | Description |
|---|---|---|---|
| `ScriptRoot` | list | package `Mods` folder | Ordered list of mod locations: local folder, UNC share or Azure blob container URL. The first location that has a file wins. |
| `ScriptSyncMode` | OnDemand / Mirror | OnDemand | OnDemand: fetch only the mod files needed for this run. Mirror: copy the whole ScriptRoot to the local cache first (also removes deleted files). |
| `UseCachedScriptsWhenOffline` | bool | false | When the ScriptRoot can't be reached: use the cached copy (true) or stop with an error (false). |
| `RequireSignedScripts` | Off / Signed / TrustedSigners | Off | Signature check for mod files before they are loaded. |
| `TrustedSigners` | list of thumbprints | - | Used with `RequireSignedScripts = TrustedSigners`. |
| `AllowedScriptSources` | list of path/URL prefixes | package folder, `C:\ProgramData\WingetFW\Scripts` | Every mod location must match one. Stops mods from unknown shares or URLs. |
| `DefaultSilent` | bool | true | Adds `-silent` when none of `-silent`, `-interactive`, `-override` is set. |
| `DefaultSource` | string | winget | Source used when none is given, for example `winget`, `msstore` or an internal REST source. |
| `AllowedSources` | list | all | Sources WingetFW may use. Respects the App Installer ADMX (Allowed/Additional Sources). |
| `Sources` | list of name + URL + type | - | Internal REST sources that WingetFW adds as SYSTEM if missing. |
| `Proxy` / `ProxyBypass` | string | - | Proxy for winget (`--proxy`, needs the winget admin setting `ProxyCommandLineOptions`, which WingetFW enables) and for WingetFW's own downloads (mods, winget bootstrap, VC++). PSADT has no proxy setting. Installers that download by themselves use the WinHTTP proxy (`netsh winhttp`). |
| `TlsCheck` | bool | false in package | Existing: add TLS 1.2 before downloads. |
| `VCRedistCheck` | bool | false in package | Existing: install the VC++ runtime for winget as SYSTEM. |

### 4.2 Security note

`HKLM\SOFTWARE\Policies` can be read by every user. A SAS token in `ScriptRoot` must be read-only
(OnDemand) or read+list (Mirror), and should be combined with `RequireSignedScripts`.

## 5. Sources

- `-source` on the command line, `Source` in the mod file, or `DefaultSource`.
- `msstore` uses the same mechanism. Store apps install machine-wide when run as SYSTEM.
- Internal REST sources are defined in `Sources` and added before winget runs.

## 6. Mods

### 6.1 Files

| File | Used for |
|---|---|
| `<ScriptRoot>\<source>\<id>.ps1` | One mod file per app, for example `\\fs01\WingetFW\Mods\winget\Adobe.Acrobat.Reader.64-bit.ps1`. |
| `<ScriptRoot>\_WingetFW.ps1` | Global mod file, same template, runs for every app. |
| `Mods\_Template.ps1` (shipped) | Template with every section empty, like PSADT's `Invoke-AppDeployToolkit.ps1`. |

No policy per app is needed: WingetFW finds the file by source and package ID.

### 6.2 Template

| Part | Content |
|---|---|
| `$Settings` | Optional hashtable with a section per action (Install, Uninstall, Repair, Upgrade): `Override`, `Custom`, `Scope`, `Locale`, `Architecture`, `Source`, `SkipDependencies`, `UninstallFirst`. Same names and option rules as the command line. |
| Install sections | `PreInstall`, `Install`, `PostInstall`, `NotInstalled` |
| Uninstall sections | `PreUninstall`, `Uninstall`, `PostUninstall`, `NotUninstalled` |
| Repair sections | `PreRepair`, `Repair`, `PostRepair`, `NotRepaired` |
| Upgrade sections | `PreUpgrade`, `Upgrade`, `PostUpgrade`, `NotUpgraded` |

- **Pre** runs before winget. Returning `$false` skips the action with exit code **69002**.
- **During** (`Install`, `Uninstall` ...) runs after winget, before the result is checked.
- **Post** runs after success, **Not...** after failure.
- ForceRepair (uninstall + install) uses the Repair sections around the whole operation.
- Import has no per-app sections; only `PreImport` / `PostImport` in the global file.
- Order: global Pre, app Pre, winget, app During/Post/Not, global During/Post/Not.

### 6.3 Loading and checks

1. Location must match `AllowedScriptSources`.
2. Signature checked when `RequireSignedScripts` is on (every run, also from cache).
3. The file is parsed without running it. It is refused if anything other than function definitions
   and `$Settings` would run at load.
4. `$Settings` is read from the parsed file without running code.
5. The file is loaded in the WingetFW session, so sections can use PSADT functions
   (`Show-ADTInstallationWelcome`, `Write-ADTLogEntry`, `Set-ADTRegistryKey` ...) and log to the same log.

### 6.4 Fetch and cache

| Mode | Behaviour |
|---|---|
| OnDemand | Asks for the exact file names for this app and action; "not found" means no mod. Blob needs a read-only SAS. |
| Mirror | Copies the whole ScriptRoot first, including deletions. Blob needs read+list. |

Cache: `C:\ProgramData\WingetFW\Cache` for SYSTEM runs (SYSTEM/Administrators only),
`%LOCALAPPDATA%\WingetFW\Cache` for user runs (the user runs these mods anyway).

### 6.5 Signing (free options)

| Option | Notes |
|---|---|
| Self-signed code signing certificate | `New-SelfSignedCertificate -Type CodeSigningCert`. Deploy the `.cer` with an Intune Trusted certificate profile to Trusted Publishers and Trusted Root. Sign with `Set-AuthenticodeSignature` and a timestamp server. Keep the `.pfx` off the mods share. |
| Internal PKI | Code signing certificate from your own CA. |
| SignPath Foundation | Free signing for open-source projects; used for the files this project ships. |

Without a certificate, protect mods with a write-protected source and `AllowedScriptSources`.

### 6.6 WDAC

With the Intune Management Extension as managed installer, files written while Intune runs WingetFW are
tagged as trusted, so unsigned mods work. Mods downloaded outside an Intune run are not tagged and must
be signed or allowed by a path rule.

## 7. Conflicting apps

`UninstallFirst` in the mod file's `$Settings.Install`: a list of entries, each one of
- a winget ID,
- an MSI product code,
- a DisplayName pattern with its uninstall command.

Each entry found on the device is removed before the install and logged. A failed removal stops the
install with that exit code. Default: none.

## 8. Exit codes

| Code | Meaning |
|---|---|
| 0 | Success, also "already installed" |
| 1641, 3010 | Success, reboot required (passed unless `-SuppressRebootPassThru`) |
| 60001 | Option rule broken or other error |
| 60008 | PSADT could not start |
| 69001 | No package specified |
| 69002 | Skipped by mod (Pre section returned `$false`) |
| other | winget return code |

## 9. State

Written only when something changes (install, uninstall, repair or upgrade succeeded).
Only data winget can't tell: managed by WingetFW, source, mod file used, last action, result and time.
The installed version is always read live from winget.

| Run as | File | Write | Read |
|---|---|---|---|
| SYSTEM | `C:\ProgramData\WingetFW\State\<id>.json` | SYSTEM, Administrators | everyone |
| User | `%LOCALAPPDATA%\WingetFW\State\<id>.json` | that user | that user, SYSTEM |

- Same fields in both, plus `Scope` and `UserSid`.
- Written to a temp file, then renamed (no half-written files).
- User files are never used for security decisions.
- History goes to the Windows event log channel `WingetFW`.

## 10. Phases

| Phase | Content | Done when |
|---|---|---|
| 0 | CI: PSScriptAnalyzer and Pester on every code change (GitHub-hosted runner); VM suite on release (self-hosted runner on the sandbox VM, manual/tag only, never for fork PRs); release workflow (zip, `.intunewin`, signing, GitHub Release from CHANGELOG). | Pipeline green on main |
| 1 | WingetFW.Core: settings reader, logging, event log channel, state files. | Pester: every settings level combination |
| 2 | ADMX/ADML, device settings (4.1), sources (5). | VM: policy beats command line beats mod beats local key beats config |
| 3 | Mods: template, discovery, fetch/cache, load checks, sections, 69002. | VM: local/UNC/blob, unsigned rejected, unknown source rejected, load check rejects top-level code |
| 4 | Conflicting apps (`UninstallFirst`). | VM: old MSI removed before install |
| 5 | Docs: `Docs\Configuration.md` (ADMX reference), `Docs\Mods.md` (mod template guide), `Docs\Signing.md`, links in README. | Reviewed |

## 11. Tests

- Pester (CI): settings order, option rules, mod parsing and load check, state file write.
- VM suite (release): existing 39 tests plus mods, policy, sources and UninstallFirst.

## 12. Open points

- WingetFW.Core location (decided in FW-1): the source is `Source\WingetFW.Core`. A device only gets what is in
  the package, so from FW-2 (when the package starts using it) the module is copied into the package folder and
  committed there too, so the folder still works when the `.intunewin` is built by hand. A unit test checks that
  the copy is the same as the source. PowerShell Gallery is not used.
- Whether Intune's "MDM wins over GP" covers imported ADMX policies (test before documenting).
