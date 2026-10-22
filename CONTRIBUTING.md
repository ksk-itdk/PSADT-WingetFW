# Contributing to PSADT-WingetFW

Maintainer: KSKITDK - <https://github.com/ksk-itdk/PSADT-WingetFW>

These notes are for anyone who changes the code. How to use WingetFW is in [README.md](README.md).

## Repo layout

| Path | Content |
|---|---|
| `Toolkit\WinGetFW\` | The package (PSAppDeployToolkit 4.1.8). Older versions are in the GitHub releases |
| `Toolkit\Detection\` | Intune detection scripts, one file per version |
| `Source\WingetFW.Core\` | Shared module for WingetFW, WingetFW Console and WingetFW-Update |
| `Build\` | Release script used by the release workflow |
| `.github\workflows\` | CI (`ci.yml`), VM tests (`vm-tests.yml`), release (`release.yml`) |
| `Tools\` | `Update-WingetFWIntuneApps.ps1` and its parameter map |
| `Tests\` | Unit tests (`Tests\Unit`), VM test suite and the last results, see [Tests/README.md](Tests/README.md) |
| `Docs\` | User documentation (linked from the README) |
| `CHANGELOG.txt` | One entry per version |
| `README.md`, `README-<version>.md` | Current version, and older versions |

## Branches and releases

- `main` holds the released version. Work in a branch per version (`wingetfw-<version>`) and merge with a pull request.
- There is one package folder, `Toolkit\WinGetFW`. The version is `AppVersion` in `Invoke-AppDeployToolkit.ps1`.
  Older versions are in the release zips on GitHub, so existing Intune apps can still be rebuilt.
- Before a release:
  1. CHANGELOG entry (see format below).
  2. Docs updated: the page in `Docs\` for the change (parameters, exit codes, configuration ...).
  3. VM suite passed, `Tests\TEST-RESULTS.md` committed.
  4. Tag with the plain version number, for example `5.0.0`. The tag starts `.github\workflows\release.yml`:
     lint and unit tests, VM suite, zip (signed when SignPath is set up) and a GitHub Release with the CHANGELOG entry.

CHANGELOG format, newest on top:

```
**Version 5.0.1 [dd/mm/yyyy]**
- Fixed an issue where ...
- Changed ...
- Added ...
```

## What may be changed in the package

The PSAppDeployToolkit template stays as it is, so it can be updated to a new PSAppDeployToolkit version.

| Path | Change |
|---|---|
| `PSAppDeployToolkit\` | No. This is the PSAppDeployToolkit module. |
| `Invoke-AppDeployToolkit.exe`, `Strings\`, `Assets\` | No. |
| `Config\config.psd1` | Only values WingetFW needs; note them in the CHANGELOG. |
| `Invoke-AppDeployToolkit.ps1` | Only the `WingetFW parameters` block, the WingetFW calls in the Install, Uninstall and Repair sections, and lines marked `# WingetFW:`. |
| `PSAppDeployToolkit.Extensions\` | Yes. All WingetFW code and `Config\WingetFW.psd1`. |
| `PSAppDeployToolkit.Extensions\WingetFW.Core\` | Only as a copy of `Source\WingetFW.Core`: change the source, then copy both files. `Tests\Unit\Package.Tests.ps1` fails when they differ. |

## Script header

Every script and module has one comment-based help block. The version history is plain text under `.NOTES`:

```
.NOTES
    Maintained by: KSKITDK
    Version      : 1.2.0

    Release notes
    1.2.0  - Newest change.
           - Second change in the same version.
    1.1.0  - Older change, continuation lines
             indented to the text.
```

- Update `Version` and add a release-notes line on top for every change. Never remove older lines.
- Don't use `.VERSION` or `.RELEASENOTES`; they break `Get-Help`.
- Keep a blank line between a `#Requires` line and `<#`, otherwise `Get-Help` ignores the help block.

## PowerShell rules

- Write `[Parameter()]`, not `[Parameter]`. Without brackets it can be read as a type and break the parameter.
- In double-quoted strings use `"${var}:"` when a colon follows a variable; `"$var:"` is read as a scope.
- Settings in `Config\WingetFW.psd1`: a missing file or setting counts as enabled.

## Exit codes in the extension module

PSAppDeployToolkit ignores `-ExitOnProcessFailure` for functions in `PSAppDeployToolkit.*` modules, so a
failed winget call in the module would not stop the deployment. The module sets the exit code itself:

| Result | Code in the module |
|---|---|
| Error | `Close-ADTSession -ExitCode <code>` (ends the deployment with that code) |
| Reboot needed (1641, 3010) | `(Get-ADTSession).SetExitCode(<code>)` (the deployment continues, Intune gets the reboot code) |

See the end of `Start-WinGetPackageFM`. New WingetFW exit codes use `6xxxx` for errors and `69xxx` for
"nothing was done"; add them to the EXIT CODES table in the README.

## Command line quoting

`Invoke-AppDeployToolkit.exe` passes the arguments to `powershell.exe -Command "try { & '...ps1' <arguments> } ..."`.

- A double-quoted value with spaces makes the script not start (exit code 1).
- An unquoted `{GUID}` loses its braces.

In README examples, tools and tests always use single quotes: `-log 'C:\Logs\my app.log'`, `-productcode '{GUID}'`.

## Tests

- Run the same checks as GitHub CI (PSScriptAnalyzer errors fail, warnings are listed; Pester tests in `Tests\Unit`):
  ```powershell
  .\Tests\Invoke-WingetFWCi.ps1
  ```
  Needs PSScriptAnalyzer and Pester 5.5 or newer. Tests marked `[admin]` only run as administrator; CI runs them.
- Changes in the package: run the VM suite ([Tests/README.md](Tests/README.md)). Add a test for every new option or fixed bug.
- `Tests\TEST-RESULTS.md` is generated by `Invoke-WingetFWVmTest.ps1`. Don't edit it by hand.

## No company data

The repo is public. Don't commit tenant IDs, company or user names, internal URLs, server names or local paths.
Use example names such as `contoso.com` and `fs01`. Search the changed files before a commit.

## Git in a synced folder

If the repo is in a OneDrive (or similar) synced folder, the sync can lock `.git\objects` folders and
`git gc` then asks to delete them. Turn automatic gc off for the repo:

```powershell
git config gc.auto 0
```
