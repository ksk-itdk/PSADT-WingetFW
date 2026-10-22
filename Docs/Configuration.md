# WingetFW 5 - Configuration

[Back to README](../README.md)

## SETTING LEVELS
WingetFW takes each setting from the first level that has a value:

| Level | Where | Typical use |
|---|---|---|
| 1. Policy | `HKLM\SOFTWARE\Policies\WingetFW`, written by Intune (imported ADMX) or GPO | Force a value for all apps on a device |
| 2. Command line | Parameters of the Intune/ConfigMgr command, for example `-proxy` | One app that needs something else |
| 3. Mod file | `$Settings` in the app's mod file, see [Mod files](Mods.md) | Settings for one app, all its deployments |
| 4. Local key | `HKLM\SOFTWARE\WingetFW`, for example from a script or remediation | Device settings that are not enforced |
| 5. Config file | `Toolkit\WinGetFW\PSAppDeployToolkit.Extensions\Config\WingetFW.psd1` | Defaults that ship with your package |
| 6. Built-in default | WingetFW | |

Every setting and the level it came from is written to the toolkit log, for example `Setting [Proxy] = [http://proxy.contoso.com:8080] from [Policy]`.

Configure the policies from Intune **or** GPO on a device, not both: both write the same key, so the last one wins.

## SETTINGS
The names are the same at every level (registry value, config file key).

| Setting | Type | Built-in default | Description |
|---|---|---|---|
| `DefaultSilent` | DWORD 1/0, `$true`/`$false` | enabled | Adds `-silent` to install, uninstall, upgrade and repair when none of `-silent`, `-interactive` and `-override` is used. |
| `DefaultSource` | string | not set | Source for install and upgrade by `-id`, `-name` or `-moniker` when there is no `-source`, for example `winget` or `msstore`. Not used for uninstall and repair (they work on installed packages). |
| `AllowedSources` | list | not set (all) | Sources WingetFW may use. `-source` or `-dependencysource` with another source stops with exit code 60001 before winget runs. |
| `Sources` | list of name = URL | not set | REST sources added in Admin mode when missing or with another URL (`winget source add --type Microsoft.Rest`). Names: letters, digits, `.`, `_`, `-`; URLs must start with `https://`. A source that can't be added is logged as a warning. |
| `Proxy` | string | not set | Proxy for winget (`--proxy`) and for WingetFW's own downloads. In Admin mode WingetFW enables the winget admin setting `ProxyCommandLineOptions`. From the policy it beats `-proxy` and `-noproxy`. |
| `ProxyBypass` | string, `;` separated | not set | Hosts that do not use the proxy for WingetFW's own downloads, for example `*.contoso.com;localhost`. winget has no bypass list. |
| `TlsCheck` | DWORD 1/0, `$true`/`$false` | enabled (package: `$false`) | Admin mode: check `SecurityProtocol` before downloads and add TLS 1.2 if it is missing. |
| `VCRedistCheck` | DWORD 1/0, `$true`/`$false` | enabled (package: `$false`) | Admin mode: install the VC++ 2015-2022 runtime (x64/x86) if it is missing. winget.exe run as SYSTEM fails with `0xC000007B` without it. |
| `ScriptRoot` | list | package `Mods` folder | Mod file locations, see [Mod files](Mods.md#settings). |
| `ScriptSyncMode` | `OnDemand` / `Mirror` | `OnDemand` | How mod files are fetched. |
| `UseCachedScriptsWhenOffline` | DWORD 1/0, `$true`/`$false` | disabled | Use cached mod files when a location can't be reached. |
| `AllowedScriptSources` | list | package folder, `C:\ProgramData\WingetFW\Scripts` | Prefixes every mod file location must start with. |
| `RequireSignedScripts` | `Off` / `Signed` / `TrustedSigners` | `Off` | Signature check for mod files. |
| `TrustedSigners` | list | not set | Certificate thumbprints for `TrustedSigners`. |

Notes:
- `-proxy` on the command line only applies to winget. WingetFW's own downloads (winget bootstrap, VC++ runtime) use `Proxy` from policy, local key or config file.
- Installers that download files by themselves use the WinHTTP proxy (`netsh winhttp`), not `Proxy`.
- The App Installer policies (Allowed sources, Additional sources) still apply to winget itself.

## POLICIES (ADMX)
The ADMX files are in the `Policies` folder of the repository: `WingetFW.admx` and `en-US\WingetFW.adml`.

- **Intune:** Devices > Configuration > Import ADMX, upload both files, then create a profile from Templates > Imported Administrative templates > WingetFW.
- **GPO:** copy `WingetFW.admx` to `PolicyDefinitions` and `WingetFW.adml` to `PolicyDefinitions\en-US` (central store or local), then use Computer Configuration > Administrative Templates > WingetFW.

| Policy | Registry |
|---|---|
| Add -silent by default | `DefaultSilent` (DWORD 1/0) |
| Default winget source | `DefaultSource` (string) |
| Allowed winget sources | subkey `AllowedSources`, values `1`, `2`, `3` ... = source names |
| Internal REST sources | subkey `Sources`, value name = source name, value = URL |
| Proxy | `Proxy` and `ProxyBypass` (strings) |
| Check TLS 1.2 before downloads | `TlsCheck` (DWORD 1/0) |
| Install the VC++ runtime for winget | `VCRedistCheck` (DWORD 1/0) |
| Mod files > Mod file locations (ScriptRoot) | subkey `ScriptRoot`, values `1`, `2`, `3` ... = locations in search order |
| Mod files > Mod file download mode | `ScriptSyncMode` (`OnDemand` or `Mirror`) |
| Mod files > Use cached mod files when a location can't be reached | `UseCachedScriptsWhenOffline` (DWORD 1/0) |
| Mod files > Allowed mod file locations | subkey `AllowedScriptSources`, values `1`, `2`, `3` ... = prefixes |
| Mod files > Require signed mod files | `RequireSignedScripts` (`Off`, `Signed` or `TrustedSigners`) |
| Mod files > Trusted signers | subkey `TrustedSigners`, values `1`, `2`, `3` ... = thumbprints |

The local key `HKLM\SOFTWARE\WingetFW` uses the same layout. A list can also be a REG_MULTI_SZ value.

### INTUNE CUSTOM PROFILE (OMA-URI)
Instead of **Import ADMX**, the policies can be set with a **Custom** profile (Devices > Configuration > Create > Windows 10 and later >
Templates > **Custom**). It uses the Policy CSP with ADMX ingestion: the device gets the ADMX in the profile, then the policies.
Use either Import ADMX or a custom profile on a device, not both.

Every row in the profile: **Data type** `String`.

**1. The ADMX** (once, in the same profile as the policies or in a profile for the same devices):

| Name | OMA-URI | Value |
|---|---|---|
| WingetFW ADMX | `./Device/Vendor/MSFT/Policy/ConfigOperations/ADMXInstall/WingetFW/Policy/WingetFWAdmx` | The whole content of `Policies\WingetFW.admx` |

**2. The policies.** The path is `./Device/Vendor/MSFT/Policy/Config/WingetFW~Policy~<category>/<policy>`, with category
`WingetFW` or, for the mod file policies, `WingetFW~Mods`:

| Policy | OMA-URI |
|---|---|
| Add -silent by default | `./Device/Vendor/MSFT/Policy/Config/WingetFW~Policy~WingetFW/DefaultSilent` |
| Default winget source | `./Device/Vendor/MSFT/Policy/Config/WingetFW~Policy~WingetFW/DefaultSource` |
| Allowed winget sources | `./Device/Vendor/MSFT/Policy/Config/WingetFW~Policy~WingetFW/AllowedSources` |
| Internal REST sources | `./Device/Vendor/MSFT/Policy/Config/WingetFW~Policy~WingetFW/Sources` |
| Proxy | `./Device/Vendor/MSFT/Policy/Config/WingetFW~Policy~WingetFW/Proxy` |
| Check TLS 1.2 before downloads | `./Device/Vendor/MSFT/Policy/Config/WingetFW~Policy~WingetFW/TlsCheck` |
| Install the VC++ runtime for winget | `./Device/Vendor/MSFT/Policy/Config/WingetFW~Policy~WingetFW/VCRedistCheck` |
| Mod file locations | `./Device/Vendor/MSFT/Policy/Config/WingetFW~Policy~WingetFW~Mods/ScriptRoot` |
| Mod file download mode | `./Device/Vendor/MSFT/Policy/Config/WingetFW~Policy~WingetFW~Mods/ScriptSyncMode` |
| Use cached mod files when a location can't be reached | `./Device/Vendor/MSFT/Policy/Config/WingetFW~Policy~WingetFW~Mods/UseCachedScriptsWhenOffline` |
| Allowed mod file locations | `./Device/Vendor/MSFT/Policy/Config/WingetFW~Policy~WingetFW~Mods/AllowedScriptSources` |
| Require signed mod files | `./Device/Vendor/MSFT/Policy/Config/WingetFW~Policy~WingetFW~Mods/RequireSignedScripts` |
| Trusted signers | `./Device/Vendor/MSFT/Policy/Config/WingetFW~Policy~WingetFW~Mods/TrustedSigners` |

The value is `<enabled/>` or `<disabled/>`, and for policies with a field one `<data>` per field. Examples:

| Kind | Example policy | Value |
|---|---|---|
| On/off | Add -silent by default off | `<disabled/>` |
| On/off | Check TLS 1.2 on | `<enabled/>` |
| Text | Default winget source | `<enabled/><data id="DefaultSource" value="winget"/>` |
| Two texts | Proxy and bypass list | `<enabled/><data id="Proxy" value="http://proxy.contoso.com:8080"/><data id="ProxyBypass" value="*.contoso.com;localhost"/>` |
| List | Allowed winget sources | `<enabled/><data id="AllowedSources" value="winget&#xF000;msstore"/>` |
| List of name = value | Internal REST sources | `<enabled/><data id="Sources" value="ContosoRest&#xF000;https://winget.contoso.com/api"/>` |
| Choice | Require signed mod files | `<enabled/><data id="RequireSignedScripts" value="TrustedSigners"/>` |
| Choice | Mod file download mode | `<enabled/><data id="ScriptSyncMode" value="Mirror"/>` |
| List | Trusted signers | `<enabled/><data id="TrustedSigners" value="0123456789ABCDEF0123456789ABCDEF01234567"/>` |
| List | Mod file locations, a share and a blob container | `<enabled/><data id="ScriptRoot" value="\\fs01\WingetFW\Mods&#xF000;https://contoso.blob.core.windows.net/mods?sv=2024-11-04&amp;sp=r&amp;sig=..."/>` |
| List | Allowed mod file locations | `<enabled/><data id="AllowedScriptSources" value="\\fs01\WingetFW\&#xF000;https://contoso.blob.core.windows.net/mods"/>` |

- `&#xF000;` separates the items of a list. In a name = value list the items are name, value, name, value ...
- The value is XML: write `&` as `&amp;` (for example in a SAS), `<` as `&lt;` and `"` as `&quot;`.
- `<disabled/>` on a policy with a field (for example Proxy) removes the value, the same as Disabled in Import ADMX.
- After a sync the values are in `HKLM\SOFTWARE\Policies\WingetFW`, with the same layout as the table above. Errors show in
  Event Viewer > Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin.

## CONFIG FILE
`Toolkit\WinGetFW\PSAppDeployToolkit.Extensions\Config\WingetFW.psd1` is in the package. It sets `TlsCheck` and `VCRedistCheck` to `$false`. Other settings can be added, for example:

```powershell
@{
    TlsCheck       = $false
    VCRedistCheck  = $false
    DefaultSource  = 'winget'
    AllowedSources = @('winget', 'msstore')
    Sources        = @{ ContosoRest = 'https://winget.contoso.com/api' }
    Proxy          = 'http://proxy.contoso.com:8080'
    ProxyBypass    = '*.contoso.com;localhost'
}
```

PSAppDeployToolkit's own settings (log folder, company name, logo) are in `Toolkit\WinGetFW\Config\config.psd1`.
