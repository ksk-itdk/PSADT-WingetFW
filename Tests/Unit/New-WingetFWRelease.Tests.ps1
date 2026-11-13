<#
.SYNOPSIS
    Pester tests for Build\New-WingetFWRelease.ps1.

.NOTES
    Maintained by: KSKITDK
    Version      : 1.2.0

    Release notes
    1.2.0  - Checks the 5.0.0 zip layout: Toolkit, newest detection scripts only, Policies, Mods and Console links.
    1.1.0  - The fake repository uses Toolkit\WinGetFW (no version in the folder name).
    1.0.0  - First version.

.LINK
    https://github.com/ksk-itdk/PSADT-WingetFW
#>

BeforeAll {
    $script = Join-Path -Path $PSScriptRoot -ChildPath '..\..\Build\New-WingetFWRelease.ps1'

    function New-FakeRepo
    {
        param ([string]$Path, [string]$AppVersion)
        $package = Join-Path -Path $Path -ChildPath 'Toolkit\WinGetFW'
        $null = New-Item -Path (Join-Path -Path $package -ChildPath 'Mods'), (Join-Path -Path $Path -ChildPath 'Toolkit\Detection'), (Join-Path -Path $Path -ChildPath 'Policies\en-US') -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path -Path $package -ChildPath 'Invoke-AppDeployToolkit.ps1') -Value @('$adtSession = @{', "    AppVersion = '$AppVersion'", '}')
        Set-Content -LiteralPath (Join-Path -Path $package -ChildPath 'Mods\_Template.ps1') -Value '# template'
        foreach ($name in 'wingetv2.0.9.ps1', 'wingetv2.0.10.ps1', 'registryversionregexv.1.0.2.ps1', 'registryversionregexv.1.0.3.ps1')
        {
            Set-Content -LiteralPath (Join-Path -Path $Path -ChildPath "Toolkit\Detection\$name") -Value '# detection'
        }
        Set-Content -LiteralPath (Join-Path -Path $Path -ChildPath 'Policies\WingetFW.admx') -Value '<admx/>'
        Set-Content -LiteralPath (Join-Path -Path $Path -ChildPath 'Policies\en-US\WingetFW.adml') -Value '<adml/>'
        Set-Content -LiteralPath (Join-Path -Path $Path -ChildPath 'CHANGELOG.txt') -Encoding UTF8 -Value @(
            '**Version 9.9.9 [01/01/2030]**'
            '- Added something new'
            '- Fixed something old'
            ''
            '**Version 9.9.8 [01/12/2029]**'
            '- Older entry'
        )
    }
}

Describe 'New-WingetFWRelease.ps1' {
    It 'Stages the package and detection scripts and writes only the matching CHANGELOG entry' {
        $repo = Join-Path -Path $TestDrive -ChildPath 'ok'
        New-FakeRepo -Path $repo -AppVersion '9.9.9'
        $out = Join-Path -Path $TestDrive -ChildPath 'out'

        $stage = & $script -Version '9.9.9' -OutputPath $out -RepoRoot $repo

        $stage | Should -Be (Join-Path -Path $out -ChildPath 'PSADT-WingetFW_9.9.9')
        Join-Path -Path $stage -ChildPath 'Toolkit\WinGetFW\Invoke-AppDeployToolkit.ps1' | Should -Exist
        @(Get-ChildItem -LiteralPath (Join-Path -Path $stage -ChildPath 'Toolkit\Detection')).Name | Sort-Object | Should -Be @('registryversionregexv.1.0.3.ps1', 'wingetv2.0.10.ps1')
        Join-Path -Path $stage -ChildPath 'Policies\WingetFW.admx' | Should -Exist
        Join-Path -Path $stage -ChildPath 'Policies\en-US\WingetFW.adml' | Should -Exist
        Join-Path -Path $stage -ChildPath 'Mods\_Template.ps1' | Should -Exist
        Get-Content -LiteralPath (Join-Path -Path $stage -ChildPath 'Mods\WingetFW mod files documentation.url') | Should -Contain 'URL=https://github.com/ksk-itdk/PSADT-WingetFW/blob/main/Docs/Mods.md'
        Get-Content -LiteralPath (Join-Path -Path $stage -ChildPath 'Console\WingetFW Console documentation.url') | Should -Contain 'URL=https://github.com/ksk-itdk/PSADT-WingetFW/blob/main/Docs/Console.md'
        $notes = Get-Content -LiteralPath (Join-Path -Path $out -ChildPath 'release-notes.md') -Raw
        $notes | Should -Match 'Added something new'
        $notes | Should -Match 'Fixed something old'
        $notes | Should -Not -Match 'Older entry'
        $notes | Should -Not -Match '\*\*Version'
    }

    It 'Fails when the package AppVersion does not match' {
        $repo = Join-Path -Path $TestDrive -ChildPath 'mismatch'
        New-FakeRepo -Path $repo -AppVersion '9.9.8'
        { & $script -Version '9.9.9' -OutputPath (Join-Path -Path $TestDrive -ChildPath 'out2') -RepoRoot $repo } | Should -Throw '*AppVersion*'
    }

    It 'Fails when there is no package folder' {
        $repo = Join-Path -Path $TestDrive -ChildPath 'nopackage'
        New-FakeRepo -Path $repo -AppVersion '9.9.9'
        Remove-Item -LiteralPath (Join-Path -Path $repo -ChildPath 'Toolkit\WinGetFW') -Recurse -Force
        { & $script -Version '9.9.9' -OutputPath (Join-Path -Path $TestDrive -ChildPath 'out3') -RepoRoot $repo } | Should -Throw '*Package not found*'
    }

    It 'Fails when CHANGELOG.txt has no entry for the version' {
        $repo = Join-Path -Path $TestDrive -ChildPath 'nochangelog'
        New-FakeRepo -Path $repo -AppVersion '9.9.7'
        { & $script -Version '9.9.7' -OutputPath (Join-Path -Path $TestDrive -ChildPath 'out4') -RepoRoot $repo } | Should -Throw '*no entry*'
    }
}
