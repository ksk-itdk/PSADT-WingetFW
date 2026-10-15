#Requires -Version 5.1

<#
.SYNOPSIS
    Runs the WingetFW CI checks: PSScriptAnalyzer and the Pester unit tests.

.DESCRIPTION
    The same checks run on GitHub (.github\workflows\ci.yml) and locally.
    1. PSScriptAnalyzer on the WingetFW code (not on the PSAppDeployToolkit module or the 4.0.8 package).
       Errors fail the run, warnings are only listed.
    2. Pester tests in Tests\Unit.

    Needs the modules PSScriptAnalyzer and Pester 5.5 or newer.

.PARAMETER SkipAnalyzer
    Only run the Pester tests.

.PARAMETER SkipPester
    Only run PSScriptAnalyzer.

.EXAMPLE
    .\Tests\Invoke-WingetFWCi.ps1

.EXAMPLE
    powershell.exe -NoProfile -File .\Tests\Invoke-WingetFWCi.ps1 -SkipAnalyzer

    Runs the unit tests in Windows PowerShell 5.1.

.NOTES
    Maintained by: KSKITDK
    Version      : 1.0.0

    Release notes
    1.0.0  - First version (phase FW-0).

.LINK
    https://github.com/ksk-itdk/PSADT-WingetFW
#>
[CmdletBinding()]
param
(
    [Parameter()]
    [switch]$SkipAnalyzer,

    [Parameter()]
    [switch]$SkipPester
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$failed = $false

if (-not $SkipAnalyzer)
{
    Import-Module -Name 'PSScriptAnalyzer'
    $analyzePaths = @(
        'Source'
        'Build'
        'Toolkit\WinGetFW5.0.0\PSAppDeployToolkit.Extensions'
        'Toolkit\WinGetFW5.0.0\Invoke-AppDeployToolkit.ps1'
        'Toolkit\Detection'
        'Tools'
        'Tests'
    )
    $settings = Join-Path -Path $repoRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'
    $findings = foreach ($path in $analyzePaths)
    {
        Invoke-ScriptAnalyzer -Path (Join-Path -Path $repoRoot -ChildPath $path) -Recurse -Settings $settings
    }
    $findings = @($findings)
    $errors = @($findings | Where-Object { $_.Severity -eq 'Error' -or $_.Severity -eq 'ParseError' })
    $findings | Sort-Object -Property ScriptPath, Line | Format-Table -Property Severity, RuleName, @{ Name = 'File'; Expression = { $_.ScriptPath.Substring($repoRoot.Length + 1) } }, Line, Message -AutoSize -Wrap | Out-String -Width 250 | Write-Host
    Write-Host ("PSScriptAnalyzer: {0} error(s), {1} warning(s)" -f $errors.Count, ($findings.Count - $errors.Count))
    if ($errors.Count) { $failed = $true }
}

if (-not $SkipPester)
{
    Import-Module -Name 'Pester' -MinimumVersion '5.5.0'
    $config = New-PesterConfiguration
    $config.Run.Path = Join-Path -Path $PSScriptRoot -ChildPath 'Unit'
    $config.Run.PassThru = $true
    $config.Output.Verbosity = 'Detailed'
    $result = Invoke-Pester -Configuration $config
    if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') { $failed = $true }
}

if ($failed) { exit 1 }
