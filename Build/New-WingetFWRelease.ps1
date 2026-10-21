#Requires -Version 5.1

<#
.SYNOPSIS
    Prepares a WingetFW release: checks the version and stages the files and release notes.

.DESCRIPTION
    Used by .github\workflows\release.yml, and can be run locally.
    1. Checks that Toolkit\WinGetFW<Version> exists and its AppVersion is <Version>.
    2. Checks that CHANGELOG.txt has an entry for <Version>.
    3. Copies the package folder and Toolkit\Detection to <OutputPath>\WingetFW-<Version>.
    4. Writes the CHANGELOG entry to <OutputPath>\release-notes.md.

.PARAMETER Version
    Release version, the same as the git tag, for example 5.0.1.

.PARAMETER OutputPath
    Folder for the staged files and release notes. Created if missing; an older stage of the same version is replaced.

.PARAMETER RepoRoot
    Repository root. Default: the parent folder of Build.

.EXAMPLE
    .\Build\New-WingetFWRelease.ps1 -Version 5.0.0 -OutputPath .\out

.NOTES
    Maintained by: KSKITDK
    Version      : 1.0.0

    Release notes
    1.0.0  - First version.

.LINK
    https://github.com/ksk-itdk/PSADT-WingetFW
#>
[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [Parameter()]
    [string]$RepoRoot = (Split-Path -Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'

$packageDir = Join-Path -Path $RepoRoot -ChildPath "Toolkit\WinGetFW$Version"
$scriptFile = Join-Path -Path $packageDir -ChildPath 'Invoke-AppDeployToolkit.ps1'
if (-not (Test-Path -LiteralPath $scriptFile -PathType Leaf)) { throw "Package not found: $scriptFile" }
$appVersion = [regex]::Match((Get-Content -LiteralPath $scriptFile -Raw), "(?m)^\s*AppVersion\s*=\s*'([^']*)'").Groups[1].Value
if ($appVersion -ne $Version) { throw "AppVersion in $scriptFile is [$appVersion], expected [$Version]." }

$changelog = Get-Content -LiteralPath (Join-Path -Path $RepoRoot -ChildPath 'CHANGELOG.txt') -Encoding UTF8
$start = -1
for ($i = 0; $i -lt $changelog.Count; $i++)
{
    if ($changelog[$i] -match "^\*\*Version $([regex]::Escape($Version)) \[") { $start = $i; break }
}
if ($start -lt 0) { throw "CHANGELOG.txt has no entry for version $Version." }
$notes = @($changelog[($start + 1)..($changelog.Count - 1)] | ForEach-Object -Begin { $done = $false } -Process {
    if ($_ -match '^\*\*Version ') { $done = $true }
    if (-not $done) { $_ }
}) -join "`n"

$null = New-Item -Path $OutputPath -ItemType Directory -Force
$stageDir = Join-Path -Path $OutputPath -ChildPath "WingetFW-$Version"
if (Test-Path -LiteralPath $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force }
$null = New-Item -Path $stageDir -ItemType Directory
Copy-Item -LiteralPath $packageDir -Destination $stageDir -Recurse
Copy-Item -LiteralPath (Join-Path -Path $RepoRoot -ChildPath 'Toolkit\Detection') -Destination $stageDir -Recurse
[IO.File]::WriteAllText((Join-Path -Path $OutputPath -ChildPath 'release-notes.md'), $notes.Trim() + "`n", (New-Object -TypeName Text.UTF8Encoding -ArgumentList $false))

Write-Output $stageDir
