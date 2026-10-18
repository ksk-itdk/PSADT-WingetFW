@{
    RootModule        = 'WingetFW.Console.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b4f2c8e1-6a3d-4f57-9c0e-2d8a7b1e5f36'
    Author            = 'KSKITDK'
    Description       = 'WingetFW Console logic: package search, manifest details, command line builder and detection scripts.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @(
        'Get-WingetFWPackageInfo'
        'Find-WingetFWPackage'
        'Get-WingetFWManifest'
        'ConvertFrom-WingetFWCommandLine'
        'New-WingetFWCommandLine'
        'New-WingetFWDetectionScript'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            ProjectUri = 'https://github.com/ksk-itdk/PSADT-WingetFW'
        }
    }
}
