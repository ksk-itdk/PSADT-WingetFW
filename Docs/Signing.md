# WingetFW 5 - Signing mod files

[Back to README](../README.md)

Mod files run as SYSTEM in admin mode. With `RequireSignedScripts`, WingetFW only runs a mod file that has a valid
Authenticode signature, so a changed or unknown file is refused even if someone can write to the mod location.

## WHEN TO SIGN
| Situation | Advice |
|---|---|
| Mod files only in the package `Mods` folder | Optional. The files are inside the `.intunewin`, which only Intune admins can change. |
| Mod files on a share or in Azure blob storage | Recommended: `RequireSignedScripts = TrustedSigners`. The location is outside the package, and a SAS in the policy can be read by users. |
| Devices with WDAC (App Control for Business) | Recommended, see [WDAC](#wdac). |

## CERTIFICATE
Any code signing certificate works. Free options:

| Option | How |
|---|---|
| Self-signed | Create it once on an admin PC (below). Trust it on the devices with an Intune Trusted certificate profile. |
| Internal PKI | Request a certificate from a Code Signing template on your own CA. The devices already trust the CA. |

Self-signed:

```powershell
# Create (keep the private key on one admin PC or in a vault, never on the mod share)
$cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=Contoso WingetFW Mods' `
    -CertStoreLocation Cert:\CurrentUser\My -KeyExportPolicy Exportable -NotAfter (Get-Date).AddYears(3)

# Public part for the devices
Export-Certificate -Cert $cert -FilePath .\ContosoWingetFWMods.cer

# Thumbprint for TrustedSigners
$cert.Thumbprint
```

Trust it on the devices: Intune > Devices > Configuration > Create > Templates > **Trusted certificate**, upload the
`.cer` file and choose **Computer certificate store - Root** (a self-signed certificate is its own root). Assign the
certificate profile and the WingetFW policy to the same devices.

## SIGN A MOD FILE

```powershell
$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object Subject -eq 'CN=Contoso WingetFW Mods'
Set-AuthenticodeSignature -FilePath '\\fs01\WingetFW\Mods\winget\7zip.7zip.ps1' -Certificate $cert `
    -HashAlgorithm SHA256 -TimestampServer 'http://timestamp.digicert.com'

# Check
Get-AuthenticodeSignature -FilePath '\\fs01\WingetFW\Mods\winget\7zip.7zip.ps1' | Format-List Status, SignerCertificate
```

- Sign again after every change; any change breaks the signature.
- Use a timestamp server: the signature then stays valid after the certificate expires.
- Save the file before signing and don't let an editor change the encoding afterwards. WingetFW checks the exact bytes of the file.

## SETTINGS
Set by policy (ADMX: WingetFW > Mod files), see [Mod files](Mods.md#settings):

| Setting | Value |
|---|---|
| Require signed mod files (`RequireSignedScripts`) | `Signed`: any valid signature from a certificate the device trusts. `TrustedSigners`: also the certificate thumbprint must be in Trusted signers. |
| Trusted signers (`TrustedSigners`) | One thumbprint per line, for example the `$cert.Thumbprint` from above. |

`TrustedSigners` is the safer choice: with `Signed`, any trusted code signing certificate on the device can sign a mod file.

A file that fails the check stops the deployment with exit code 60001. The log says why, for example
`is not validly signed (NotSigned)` or `is signed by [CN=...] (...), which is not in TrustedSigners`.
The signature is checked on every run, also for cached copies.

## WDAC
- WingetFW reads a mod file as text and runs it in its own PowerShell session. Windows does not check it as a script file,
  so WDAC script rules do not apply to mod files. `RequireSignedScripts` is the check: turn it on for WDAC devices.
- With Intune as managed installer, files written while Intune runs WingetFW are trusted by WDAC. This covers the WingetFW
  package and the installers winget runs, not mod files fetched outside an Intune deployment.

## SIGNING WINGETFW ITSELF
The release workflow can sign the files of a WingetFW release with SignPath (free for open-source projects).
See `.github\workflows\release.yml` and [CONTRIBUTING.md](../CONTRIBUTING.md#branches-and-releases).
