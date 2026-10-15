# WingetFW Console - Project spec

> Status: draft. Depends on: [WingetFW](Spec-WingetFW.md) (WingetFW.Core, settings, mods, state).
> Related: [WingetFW-Update](Spec-WingetFW-Update.md). Phase plan for all three: [Phases](Phases.md).

## 1. Purpose

A desktop tool for admins that turns "I want app X in Intune" into a finished, tested WingetFW app,
and gives an overview of all WingetFW apps already deployed. It writes nothing on client devices;
it builds packages, commands, detection scripts and mod files, and publishes them.

## 2. Users and goals

| Goal | Today | With the Console |
|---|---|---|
| Find the right package ID | `winget search` by hand | Search with details from the manifest |
| Build the install command | Typed by hand, quoting rules to remember | Built from choices, quoting done right |
| Detection script | Copied and edited | Generated from template |
| Create the Intune app | Portal, several screens | One action |
| Update WingetFW in existing apps | `Tools\Update-WingetFWIntuneApps.ps1` | Same logic, with a list and preview |
| Pre/post scripts per app | Written from scratch | Created from the mod template |

## 3. Features

### 3.1 Search and details

- Search winget (and `msstore`, internal REST sources) by name, ID, publisher, tag.
- Show manifest details: versions, installer types, scopes, architectures, locales, install switches,
  dependencies, release date, product code.

### 3.2 Build

- Command line for `Invoke-AppDeployToolkit.exe` with the chosen action and options. Follows the WingetFW
  option rules (same checks as 60001) and the quoting rule: values with spaces in single quotes.
- Uninstall command for the same app.
- Detection script from the shipped templates (winget version check or registry version check).
- `.intunewin` of the WingetFW package (the same package for all apps).

### 3.3 Publish

| Target | How |
|---|---|
| Intune | Microsoft Graph: create Win32 app, upload `.intunewin`, set commands, detection, requirements, return codes (incl. 69002), optional assignments. Reuses the upload code of `Tools\Update-WingetFWIntuneApps.ps1`. |
| ConfigMgr | ConfigurationManager PowerShell module: application, deployment type, content, detection. |

### 3.4 Inventory

List of all Intune (or ConfigMgr) apps that run WingetFW, with:
- WingetFW version in the app, winget package ID, action and options,
- mod file found for the app (and its signature status),
- detection type, assignments,
- warnings, for example old setup file name, `ServiceUI`, unquoted values with spaces.

### 3.5 Upgrade WingetFW in apps

- Select apps in the inventory, preview the changes, apply. Same rules as the update tool
  (`Tools\WingetFW-ParameterMap.psd1`).
- Dry-run shows what would change without writing.

### 3.6 Mods and settings

- Create a mod file for an app from the template, edit sections, save to the ScriptRoot.
- Sign the file when a code signing certificate is available.
- Run the mod load check (same as WingetFW) before saving.
- Show the effective settings for a test device (policy, local key, mod, config) with the source of each.

## 4. Technology

| Phase | Technology | Why |
|---|---|---|
| First | PowerShell + WPF (XAML) | Same language as WingetFW, reuses WingetFW.Core, nothing to compile. |
| Later | .NET (WPF or WinUI) | Only if the PowerShell version gets too slow or too large. |

- Graph sign-in: delegated (admin signs in), Microsoft.Graph.Authentication. Permissions:
  `DeviceManagementApps.ReadWrite.All` (and `Group.Read.All` for assignments).
- No secrets stored by the Console.

## 5. Security

- Uses the admin's own sign-in; actions are limited to that admin's Intune role.
- Mod files are written only to locations in `AllowedScriptSources`.
- Changes to existing apps always show a preview first.

## 6. Phases

| Phase | Content | Done when |
|---|---|---|
| 1 | Search, details, command line, detection script (no publishing). | Output matches hand-made apps that pass the VM suite |
| 2 | Intune publish (create app, upload, assign). | App created in a test tenant installs on the VM |
| 3 | Inventory and WingetFW upgrade of apps (replaces the update tool's CLI as main path; CLI stays). | Inventory lists all test apps correctly; upgrade dry-run equals update tool output |
| 4 | Mod editor, signing, effective settings view. | Mod created in the Console runs on the VM |
| 5 | ConfigMgr publish. | App created in a lab site installs |

## 7. Tests

- Pester: command line builder (option rules, quoting), detection script generator, inventory parser.
- Graph calls tested against a test tenant; no tenant data in the repo.

## 8. Open points

- One window with tabs, or separate windows per task.
- Whether to also show device results (needs WingetFW-Update reporting or Intune install status).
