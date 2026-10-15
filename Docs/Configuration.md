# WingetFW 5.0.0 - Configuration

[Back to README](../README.md)

## CONFIGURATION
`Toolkit\WinGetFW5.0.0\PSAppDeployToolkit.Extensions\Config\WingetFW.psd1`:

| Setting | Value in package | Description |
|---|---|---|
| `WingetFW_TlsCheck` | `$false` | Admin mode: check `SecurityProtocol` before downloads and add TLS 1.2 if it is missing. |
| `WingetFW_VCRedistCheck` | `$false` | Admin mode: install the VC++ 2015-2022 runtime (x64/x86) if it is missing. winget.exe run as SYSTEM fails with `0xC000007B` without it. |

If the file or a setting is missing, the check runs.

PSAppDeployToolkit's own settings (log folder, company name, logo) are in `Toolkit\WinGetFW5.0.0\Config\config.psd1`.
