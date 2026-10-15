# WingetFW-Update - Project spec

> Status: draft. Depends on: [WingetFW](Spec-WingetFW.md) (WingetFW.Core, settings, mods, state).
> Related: [WingetFW Console](Spec-WingetFW-Console.md). Phase plan for all three: [Phases](Phases.md).

## 1. Purpose

Keeps winget apps up to date on managed devices, with control over what, when and for whom.
Own design; ideas are taken from Winget-AutoUpdate (Romanitho), but it is not a fork.

It uses the same policy key, mod files and state as WingetFW, so an app installed with WingetFW
keeps its settings and pre/post scripts when it is upgraded.

## 2. Run modes

| Mode | How | When to use |
|---|---|---|
| Scheduled task | SYSTEM task for machine apps, user task for user apps. Each can be turned off by policy. | Normal devices |
| Intune | Remediation script or Win32 app that runs the same engine. | WDAC devices (managed installer, see 7) or when no local tasks are wanted |
| Manual | Run the script by hand. | Testing, support |

### 2.1 Enrollment (Autopilot)

WingetFW-Update must not run while the Enrollment Status Page (ESP) is running: upgrades then compete
with the apps ESP installs and can make enrollment time out.

- **Admins:** deploy WingetFW-Update so it starts after enrollment, and do not add it as a blocking app
  in the ESP. The README says this.
- **Check:** at the start of every run the engine checks whether ESP is still running. If it is, the run
  is logged and stopped without updating anything:

| Run mode | Result while ESP runs |
|---|---|
| Scheduled task | Exit 0, the next scheduled run tries again |
| Intune Win32 app | Exit 1618 (Intune retries later) |
| Intune remediation | Detection returns 0 (no remediation now) |
| Manual | Message and exit 0; `-IgnoreEsp` for testing |

How ESP is detected is decided in UPD-1 after tests. Candidates: the enrollment `FirstSync` values in
`HKLM\SOFTWARE\Microsoft\Enrollments\<id>\FirstSync`, the `defaultuser0` account being logged on, and the
ESP processes (`CloudExperienceHostBroker.exe`).

## 3. Settings

Same key and order as WingetFW (`HKLM\SOFTWARE\Policies\WingetFW`, then local key, config, default).
There is no command line per app; per-app values come from the mod file.

| Setting | Default | Description |
|---|---|---|
| `EnableSystemTask` | true | Create and run the SYSTEM task. |
| `EnableUserTask` | true | Create and run the user task. |
| `Schedule` | daily | Run times (daily/weekly, time, random delay). |
| `UpdateScope` | All | `All` (minus `BlockList`), `AllowList`, or `ManagedOnly` (only apps with a WingetFW state file). |
| `BlockList` / `AllowList` | - | Package IDs. |
| `Ring` | from device ID | `Pilot`, `Early`, `Broad`. Set by policy (Intune group targeting) or computed from a hash of the device ID. |
| `RingDelayDays` | 0 / 3 / 7 | Days after release before each ring gets an update. |
| `MinReleaseAgeDays` | 0 | Wait at least this many days after release. |
| `SkipMajorZero` | false | Skip x.0 releases. |
| `MaxMajorJump` | - | Don't upgrade across more than N major versions. |
| `MaintenanceWindow` | - | Times when updates may run. |
| `SkipOnMetered` / `SkipOnBattery` | true / true | Skip on metered connection or battery. |
| `AutoPinAfterFailures` | 3 | Pin an app after N failed upgrades in a row. |
| `ScriptSyncMode` | Mirror | Fetch all mods first (WingetFW default is OnDemand). |

Release date comes from the manifest `ReleaseDate`; if missing, from the commit date in winget-pkgs.

## 4. Upgrade flow per run

1. Stop if ESP is running (2.1).
2. Run hook `PreRun` in `<ScriptRoot>\_WingetFW-Update.ps1` (stop the run if it returns `$false`).
3. Sync mods (Mirror).
4. Get upgradable apps from winget, apply scope, pins, ring and release rules.
5. For each app: global and app `PreUpgrade`, `$Settings.Upgrade`, winget upgrade, `Upgrade`,
   `PostUpgrade` or `NotUpgraded` - the same sections WingetFW uses.
6. Update state files, write event log, count failures (auto pin).
7. Run hook `PostRun`.
8. Write report.

## 5. User experience

PSAppDeployToolkit 4 for messages: close running apps, deferrals, toast notifications, restart prompts.
Silent by default; the mod file decides when to show something (for example in `PreUpgrade`).

## 6. Pins, exclusions and rollback

- Per-app pin through `winget pin` (also set by the Console or a remediation).
- Exclude by device or user through policy targeting in Intune or GPO.
- Rollback: install the previous version (`--version`) when the new one fails and the app supports it;
  the version before the upgrade is stored in the state file.

## 7. Security and WDAC

- Mods: same checks as WingetFW (allowed sources, signature, load check).
- WDAC with the Intune managed installer: files fetched by a scheduled task are not tagged, so under WDAC
  either sign all mods or use Intune mode.
- Scheduled task files are installed to `C:\Program Files\WingetFW-Update` (Administrators only).

## 8. Reporting

| Step | Content |
|---|---|
| Local | JSON summary per run in `C:\ProgramData\WingetFW\Reports` and the `WingetFW` event log channel. |
| Intune mode | Short summary as remediation output. |
| Central | Log Analytics through the Logs Ingestion API; Workbook or Power BI report. |

Health check: last run time, failures, pinned apps, winget health.

## 9. Phases

| Phase | Content | Done when |
|---|---|---|
| 1 | Engine: ESP check, get upgrades, scope, block/allow lists, upgrade with mod sections, state, event log. Manual mode. | VM: upgrades only allowed apps, mod sections run, stops during ESP |
| 2 | Scheduled tasks (SYSTEM + user), schedule, policy on/off. | VM: tasks created and removed by policy |
| 3 | Intune mode (remediation and Win32 app). | Works on a WDAC test device |
| 4 | Rings and release rules, pins, auto pin, maintenance window, metered/battery. | Pester per rule; VM per ring |
| 5 | PSADT user experience, rollback. | VM: deferral and restart prompt |
| 6 | Reporting (local, remediation output, Log Analytics) and health check. | Data visible in Workbook |

## 10. Tests

- Pester: every filter rule (scope, ring, release age, x.0, major jump, pin) with sample winget output.
- VM suite: task and Intune modes, mods during upgrade, rollback.

## 11. Prior art

- Winget-AutoUpdate (Romanitho) - ideas for tasks, lists and notifications.
- WingetIntune (svrooij), IntuneWin32App (MSEndpointMgr) - Intune publishing.
- Intune Enterprise App Management, Patch My PC - commercial alternatives.

## 12. Open points

- Separate repo or folder in this repo.
- Which ESP detection is reliable (2.1); test on an Autopilot device with and without a user ESP phase.
- Whether the user task needs its own mod cache sync or uses the SYSTEM cache read-only.
- Release date lookup from winget-pkgs without a GitHub token (rate limits).
