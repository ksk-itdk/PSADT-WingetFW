@{
    RootModule        = 'WingetFW.Core.psm1'
    ModuleVersion     = '1.2.0'
    GUID              = '5d0c7a3e-2f4b-4c1e-9a6d-8b7e3f1c2a90'
    Author            = 'KSKITDK'
    Description       = 'Shared functions for WingetFW, WingetFW Console and WingetFW-Update: settings, logging, event log and state files.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-WingetFWSetting'
        'Write-WingetFWLog'
        'Register-WingetFWEventLog'
        'Write-WingetFWEvent'
        'Get-WingetFWState'
        'Set-WingetFWState'
        'Import-WingetFWMod'
        'Invoke-WingetFWModSection'
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
