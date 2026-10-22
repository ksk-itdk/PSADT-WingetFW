@{
    # WingetFW - Configuration for the PSAppDeployToolkit.Extensions module.
    # Loaded by PSAppDeployToolkit.Extensions.psm1 from this folder. This is setting level 5 of 6:
    # policy (HKLM\SOFTWARE\Policies\WingetFW), command line, mod file, local key (HKLM\SOFTWARE\WingetFW), this file, built-in default.
    # Other settings (DefaultSilent, DefaultSource, AllowedSources, Sources, Proxy, ProxyBypass) can be added here too, see Docs\Configuration.md.

    # Check SecurityProtocol before downloads and add TLS 1.2 if it is missing. Options: $true, $false. Default: $true.
    TlsCheck = $false

    # Admin mode: install the VC++ 2015-2022 runtime (x64/x86) if missing. winget.exe as SYSTEM fails with 0xC000007B without it. Options: $true, $false. Default: $true.
    VCRedistCheck = $false
}
