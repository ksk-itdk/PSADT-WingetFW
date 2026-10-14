@{
    # WingetFW - Configuration for the PSAppDeployToolkit.Extensions module.
    # Loaded by PSAppDeployToolkit.Extensions.psm1 from this folder. If this file or a setting is missing, the default is used.

    # Check SecurityProtocol before downloads and add TLS 1.2 if it is missing. Options: $true, $false. Default: $true.
    WingetFW_TlsCheck = $false

    # Admin mode: install the VC++ 2015-2022 runtime (x64/x86) if missing. winget.exe as SYSTEM fails with 0xC000007B without it. Options: $true, $false. Default: $true.
    WingetFW_VCRedistCheck = $false
}
