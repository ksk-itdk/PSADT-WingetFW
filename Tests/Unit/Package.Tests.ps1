<#
.SYNOPSIS
    Pester tests for the WingetFW package files in Toolkit\WinGetFW (no PSADT session needed).

.NOTES
    Maintained by: KSKITDK
    Version      : 1.0.1

    Release notes
    1.0.1  - The package is in Toolkit\WinGetFW (no version in the folder name).
    1.0.0  - First version: WingetFW.Core copy in the package equals Source\WingetFW.Core.

.LINK
    https://github.com/ksk-itdk/PSADT-WingetFW
#>

BeforeDiscovery {
    $sourceDir = Join-Path -Path $PSScriptRoot -ChildPath '..\..\Source\WingetFW.Core'
    $coreFiles = @(Get-ChildItem -LiteralPath $sourceDir -File | ForEach-Object { @{ Name = $_.Name } })
}

BeforeAll {
    $sourceDir = Join-Path -Path $PSScriptRoot -ChildPath '..\..\Source\WingetFW.Core'
    $extensionsDir = Join-Path -Path $PSScriptRoot -ChildPath '..\..\Toolkit\WinGetFW\PSAppDeployToolkit.Extensions'
    $packageCoreDir = Join-Path -Path $extensionsDir -ChildPath 'WingetFW.Core'
}

Describe 'WingetFW.Core in the package' {
    It '<Name> in the package is the same as in Source\WingetFW.Core' -ForEach $coreFiles {
        $packageFile = Join-Path -Path $packageCoreDir -ChildPath $Name
        $packageFile | Should -Exist
        (Get-FileHash -LiteralPath $packageFile).Hash | Should -Be (Get-FileHash -LiteralPath (Join-Path -Path $sourceDir -ChildPath $Name)).Hash -Because 'copy Source\WingetFW.Core to the package after a change'
    }

    It 'The package has no extra files in WingetFW.Core' {
        @(Get-ChildItem -LiteralPath $packageCoreDir -File).Count | Should -Be @(Get-ChildItem -LiteralPath $sourceDir -File).Count
    }

    It 'PSAppDeployToolkit.Extensions loads WingetFW.Core as a nested module' {
        $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path -Path $extensionsDir -ChildPath 'PSAppDeployToolkit.Extensions.psd1')
        $manifest.NestedModules | Should -Contain 'WingetFW.Core\WingetFW.Core.psd1'
    }
}
