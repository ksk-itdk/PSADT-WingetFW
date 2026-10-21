<#
.SYNOPSIS
    Pester tests for Build\New-WingetFWRelease.ps1.

.NOTES
    Maintained by: KSKITDK
    Version      : 1.0.0

    Release notes
    1.0.0  - First version.

.LINK
    https://github.com/ksk-itdk/PSADT-WingetFW
#>

BeforeAll {
    $script = Join-Path -Path $PSScriptRoot -ChildPath '..\..\Build\New-WingetFWRelease.ps1'

    function New-FakeRepo
    {
        param ([string]$Path, [string]$PackageVersion, [string]$AppVersion)
        $package = Join-Path -Path $Path -ChildPath "Toolkit\WinGetFW$PackageVersion"
        $null = New-Item -Path $package, (Join-Path -Path $Path -ChildPath 'Toolkit\Detection') -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path -Path $package -ChildPath 'Invoke-AppDeployToolkit.ps1') -Value @('$adtSession = @{', "    AppVersion = '$AppVersion'", '}')
        Set-Content -LiteralPath (Join-Path -Path $Path -ChildPath 'Toolkit\Detection\wingetv9.9.9.ps1') -Value '# detection'
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
        New-FakeRepo -Path $repo -PackageVersion '9.9.9' -AppVersion '9.9.9'
        $out = Join-Path -Path $TestDrive -ChildPath 'out'

        $stage = & $script -Version '9.9.9' -OutputPath $out -RepoRoot $repo

        $stage | Should -Be (Join-Path -Path $out -ChildPath 'WingetFW-9.9.9')
        Join-Path -Path $stage -ChildPath 'WinGetFW9.9.9\Invoke-AppDeployToolkit.ps1' | Should -Exist
        Join-Path -Path $stage -ChildPath 'Detection\wingetv9.9.9.ps1' | Should -Exist
        $notes = Get-Content -LiteralPath (Join-Path -Path $out -ChildPath 'release-notes.md') -Raw
        $notes | Should -Match 'Added something new'
        $notes | Should -Match 'Fixed something old'
        $notes | Should -Not -Match 'Older entry'
        $notes | Should -Not -Match '\*\*Version'
    }

    It 'Fails when the package AppVersion does not match' {
        $repo = Join-Path -Path $TestDrive -ChildPath 'mismatch'
        New-FakeRepo -Path $repo -PackageVersion '9.9.9' -AppVersion '9.9.8'
        { & $script -Version '9.9.9' -OutputPath (Join-Path -Path $TestDrive -ChildPath 'out2') -RepoRoot $repo } | Should -Throw '*AppVersion*'
    }

    It 'Fails when there is no package folder for the version' {
        $repo = Join-Path -Path $TestDrive -ChildPath 'nopackage'
        New-FakeRepo -Path $repo -PackageVersion '9.9.9' -AppVersion '9.9.9'
        { & $script -Version '9.9.7' -OutputPath (Join-Path -Path $TestDrive -ChildPath 'out3') -RepoRoot $repo } | Should -Throw '*Package not found*'
    }

    It 'Fails when CHANGELOG.txt has no entry for the version' {
        $repo = Join-Path -Path $TestDrive -ChildPath 'nochangelog'
        New-FakeRepo -Path $repo -PackageVersion '9.9.7' -AppVersion '9.9.7'
        { & $script -Version '9.9.7' -OutputPath (Join-Path -Path $TestDrive -ChildPath 'out4') -RepoRoot $repo } | Should -Throw '*no entry*'
    }
}
