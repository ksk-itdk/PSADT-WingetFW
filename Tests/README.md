# WingetFW tests

Test suite for the WingetFW package. It runs every WingetFW parameter for all winget actions on a sandbox VM through `Invoke-AppDeployToolkit.exe` (5.0.0) or `Deploy-Application.exe` (4.0.8), the same way Intune runs it. Each run is then checked against the toolkit log and the state of the machine.

> The suite tests **WingetFW 5.0.0** (`Toolkit/WinGetFW5.0.0`) by default. Use `-Package WinGetFW` to test **WingetFW 4.0.8** ([README-4.0.8.md](../README-4.0.8.md)).

Results of the last run: [TEST-RESULTS.md](TEST-RESULTS.md)

## Files

| File | Purpose |
|---|---|
| `Invoke-WingetFWVmTest.ps1` | Run locally. Copies the package and suite to the VM, runs the suite, fetches the results and writes `TEST-RESULTS.md`. |
| `Invoke-WingetFWTestSuite.ps1` | Runs on the VM. Contains all tests. |
| `TEST-RESULTS.md` | Generated report (pass/fail per test, parameter coverage, winget command lines, log excerpts). Do not edit by hand. |
| `results/WingetFW-TestResults.log` | Full readable log of the last run. |
| `results/WingetFW-TestResults.json` | Machine-readable results, the source for `TEST-RESULTS.md`. |
| `results/console.txt` | Console output of the last run. |
| `Invoke-WingetFWCi.ps1` | Runs PSScriptAnalyzer and the Pester unit tests in `Unit\` (no VM needed). Used by GitHub CI. |

## Run the tests

```powershell
cd PSADT-WingetFW\Tests
.\Invoke-WingetFWVmTest.ps1                 # full run of WingetFW 5.0.0, about 12 minutes, do not interrupt
.\Invoke-WingetFWVmTest.ps1 -Package WinGetFW   # full run of WingetFW 4.0.8
.\Invoke-WingetFWVmTest.ps1 -ReportOnly     # only rebuild TEST-RESULTS.md from results\*.json
```

Do not stop a run halfway. Processes on the VM keep running after the SSH session is closed, and they collide with the next run. The suite refuses to start when a `Deploy-Application` process is still running on the VM.

## Prerequisites

| What | Value |
|---|---|
| Sandbox VM | `192.168.58.129`, Windows 11, OpenSSH server |
| SSH user | `TEST` (local administrator) |
| SSH key | `%USERPROFILE%\.ssh\wingetfw_sandbox`, no passphrase, public key in `C:\ProgramData\ssh\administrators_authorized_keys` on the VM |
| PsExec | `C:\temp\PSTools\PsExec64.exe` on the VM |
| Working folder on VM | `C:\temp\wingetfw-vmtest` (outside user profiles, so SYSTEM can read it) |
| Internet on VM | winget source, 7-Zip/jq/Postman downloads, GitHub API for the 7-Zip manifest |

Defaults can be changed with `-ComputerName`, `-UserName`, `-KeyFile` and `-RemoteRoot`.

## Self-hosted runner (CI)

The VM suite can't run on GitHub-hosted runners, because it needs the sandbox VM, PsExec and SYSTEM rights.
A self-hosted GitHub Actions runner is installed on the sandbox VM for it. The workflow is
[.github/workflows/vm-tests.yml](../.github/workflows/vm-tests.yml); the release workflow
([release.yml](../.github/workflows/release.yml)) calls it for every version tag. This section is the runner setup.

### Rules

| Rule | Why |
|---|---|
| The VM job runs only on a manual start (`workflow_dispatch`) or a version tag (`push: tags`). | The suite takes about 12 minutes and changes the VM. |
| The VM job never runs on `pull_request`. | The repo is public. A pull request from a fork could run its own code on the VM. Only maintainers can start a manual run or push a tag. |
| The runner is registered to this repository only, with the label `wingetfw-vm`. | Jobs from other repositories can't use it. The workflow picks it with `runs-on: [self-hosted, wingetfw-vm]`. |
| PSScriptAnalyzer and Pester run on GitHub-hosted runners on every push and pull request. | They don't touch the VM. |
| Repository setting **Actions > General > Fork pull request workflows**: require approval for all outside collaborators. | Extra safety if a workflow is changed by mistake. |

### Setup

1. Set up the VM as in [Prerequisites](#prerequisites).
2. On GitHub: repository **Settings > Actions > Runners > New self-hosted runner > Windows x64**.
   Run the download commands shown there in an admin PowerShell in `C:\actions-runner` on the VM.
3. Configure the runner as a service:
   ```powershell
   .\config.cmd --url https://github.com/ksk-itdk/PSADT-WingetFW --token <token> --labels wingetfw-vm --runasservice
   ```
   - `<token>` is shown on the GitHub page and expires after one hour. Don't save it anywhere.
   - When asked for the service account, enter `.\TEST` and type its password at the prompt.
     The job then connects by SSH as `TEST` to `localhost`, the same way a run from your own PC does.
4. Copy the private key `wingetfw_sandbox` to `C:\Users\TEST\.ssh\` (only `TEST`, SYSTEM and Administrators may read it).
   The public key is already in `C:\ProgramData\ssh\administrators_authorized_keys`.
5. Check that the runner shows as **Idle** under **Settings > Actions > Runners**.
6. Take a new VM snapshot, so a revert keeps the runner.
   GitHub removes a runner that has been offline for more than 14 days; register it again with a new token if that happens.

### Start a run

**Actions > VM tests > Run workflow**, optionally with a package folder (for example `WinGetFW5.0.0`).
The job fails when a test is not `PASS`; `TEST-RESULTS.md` and `results\` are attached to the run as `vm-test-results`.
Only one VM run can run at a time.

## How a test runs

1. Admin-mode tests run `Deploy-Application.exe` **as SYSTEM through PsExec** (`PsExec64.exe -s`), like Intune. winget in `C:\Program Files\WindowsApps` cannot be started directly by an admin user ("Access is denied").
2. User-mode tests run `Deploy-Application.exe` as the SSH user without PsExec, with `-DeployMode NonInteractive` so an error dialog cannot block the run.
3. Before every run a marker line is written to the toolkit log (`C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\<app>_WingetFW_<version>_EN_01_PSAppDeployToolkit_<DeploymentType>.log`). The line has component `WingetFW-Test` and contains the test ID, the run-as account and the full command, including PsExec.
4. After the run, only the new part of the toolkit log is read. Each test checks:
   - the exit code of `Deploy-Application.exe`
   - the winget command line from the `Execute-Process` log line (expected options present, unsupported options absent)
   - expected or forbidden log messages (validation errors, `Skipping -<option>`)
   - the state on the machine (7-Zip version and MSI/EXE, portable files, user package folder)
5. The winget admin settings needed by some options (`LocalManifestFiles`, `InstallerHashOverride`, `LocalArchiveMalwareScanOverride`, `ProxyCommandLineOptions`) are enabled for the run and restored afterwards. The original state is kept in `C:\temp\wingetfw-vmtest\winget-adminsettings-original.json` until the run completes, so an aborted run is restored by the next one.

## Test groups

| Group | IDs | What is tested |
|---|---|---|
| Validation | V01-V10 | Conflicting options, options a winget action does not support, and `-header` without `-source` stop with exit code 60001 before winget runs. |
| Exe quoting | Q01-Q03 | How `Deploy-Application.exe` passes arguments to PowerShell (see Known issues). |
| Functional | F01-F15 | Install, upgrade, repair, force repair, uninstall and import with 7-Zip (`7zip.7zip`): older MSI (WiX) version, local manifest, import file, EXE with `-override`, product code, moniker, name, proxy, `-OverrideAPPName`, install of an already installed package (exit 0). |
| Portable | P01-P04 | `-rename`, `-location`, `-preserve` and `-purge` with the portable package `jqlang.jq`. |
| Settings | S01-S12 | Setting levels policy > command line > local key > config file (with `Proxy`), `DefaultSilent`, `DefaultSource`, `AllowedSources`, `Sources` and `TlsCheck`. The suite writes `HKLM\SOFTWARE\Policies\WingetFW`, `HKLM\SOFTWARE\WingetFW` and the package config file on the VM, and resets them before every S test and at the end. |
| Mod files | M01-M15 | Order of the global and app sections, `$Settings`, command line beats `$Settings`, 69002, Not sections on failure, load check, unsigned and signed files, `AllowedScriptSources`, a read-only SMB share (`\\localhost\WingetFWMods`), Azure blob simulated with a local HTTPS web server that needs the SAS (OnDemand, Mirror, SAS masked, wrong SAS = 403), offline with and without the cache, user mode. The suite adds a test code signing certificate, a TLS certificate for `https://localhost:8443` and the SMB share on the VM, and removes them at the end. |
| Conflicting apps | C01-C04 | The `PreInstall` example from the template: `Uninstall-ADTApplication` by MSI product code and by name removes an older 7-Zip MSI before jq is installed, an app that is not installed is skipped, and an uninstall that fails (a fake app whose uninstall returns 1603) stops the deployment with 60001 before winget runs. |
| User mode | U01-U06 | `-Mode User` without PsExec: install and uninstall `jqlang.jq` (portable) and `Postman.Postman` (EXE installer with `Scope: user`). U05 simulates the first-logon race: `LOCALAPPDATA` points to a folder where `Microsoft\WindowsApps` is linked in (junction) as soon as WingetFW has logged retry attempt 2, so the retry is always tested. The junction is removed with `rmdir`, which removes only the link. |

Paths with spaces are used on purpose (`C:\temp\wingetfw-vmtest\path with spaces\...`) to test the quoting of `-log`, `-wingetmanifest`, `-importfile` and `-location`.

Informational tests accept more than one exit code, because the outcome depends on the package or the network rather than on WingetFW. They still check the winget command line:
- F04/F05: the 7-Zip MSI repair itself can fail in winget.
- F13: dummy proxy, so the network call is expected to fail.

## Known issues found by the tests

| Issue | Impact | Workaround / fix |
|---|---|---|
| `Deploy-Application.exe` (PSADT v3) removes double quotes and runs the arguments through `powershell.exe -Command & { ... }` | A value in double quotes that contains spaces is split. `Deploy-Application.ps1` never starts, but the exit code is **0** (Q01). An unquoted `{GUID}` loses its braces (Q03). | Put values with spaces or special characters in **single quotes** in Intune command lines, for example `-log 'C:\Logs\my app.log'` or `-productcode '{GUID}'` (Q02). |
| `-header` without `-source` | winget rejects the call with `0x8A150002`: "The optional header is not applicable without specifying a source". With `-source winget`, winget accepts the call but ignores the header, because headers are only used by REST sources (F02). | **Fixed:** `Start-WinGetPackageFM` now stops with 60001 before winget runs (V10). |
| `winget repair` of the 7-Zip MSI returns `0x8A15007B` (repair failed) | winget limitation for this package, not WingetFW. `-ForceRepair` works (F06). | Use `-ForceRepair` for packages without working repair support. |
| PSADT v3 `Show-DialogBox` is only skipped in `NonInteractive` mode | Any error caught by the main `Catch` (for example a parameter conflict) in a user session with `-DeployMode Silent` shows an error dialog. `Exit-Script` only runs after OK is clicked or after `InstallationUI_Timeout` (6900 s), which is longer than the default Intune install timeout. SYSTEM installs switch to NonInteractive by themselves (session 0). | Use `-DeployMode NonInteractive` for user-mode deployments. Fixed in the PSADT v4 template (dialog is commented out). |
| Package does not support user scope | `-Mode User` with a machine-only package fails. Example: `7zip.7zip` has `Scope: machine` and `ElevationRequirement: elevatesSelf`. | Only use `-Mode User` for packages whose manifest has `Scope: user`, or no scope and no elevation (for example `Postman.Postman`, portable `jqlang.jq`). |

winget return codes: <https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md>

## Adding a test

Add an `Invoke-Test` call to `Invoke-WingetFWTestSuite.ps1`:

```powershell
Invoke-Test -Id 'F15' -Title 'Install: ...' -ArgList @('Install', '-id', 'Publisher.App', '-exact', '-silent') `
    -ExpectExit @(0) `
    -Flags @(, @('--id Publisher.App', '--silent')) `
    -NotFlags @(, @('--accept-package-agreements')) `
    -ExpectLog @('regex that must be in the toolkit log') `
    -State { [PSCustomObject]@{ Ok = (Test-Path 'C:\Program Files\App\app.exe'); Text = 'app.exe exists' } }
```

- `-ArgList` starts with the DeploymentType. `-DeployMode` and `-Mode User` are added automatically.
- `-Flags` and `-NotFlags` hold one array per winget call, in call order. Write `@(, @(...))` for a single call.
- `-Mode User` runs without PsExec.
- `-RawArgs` passes a literal argument string to `Deploy-Application.exe`, used to test quoting.
- `-Pre` runs a script block before the deployment, for example to create a file.
- `-ExpectExit $null` accepts any exit code.
