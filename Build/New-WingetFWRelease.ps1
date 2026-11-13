#Requires -Version 5.1

<#
.SYNOPSIS
    Prepares a WingetFW release: checks the version and stages the files and release notes.

.DESCRIPTION
    Used by .github\workflows\release.yml, and can be run locally.
    1. Checks that Toolkit\WinGetFW exists and its AppVersion is <Version>.
    2. Checks that CHANGELOG.txt has an entry for <Version>.
    3. Stages <OutputPath>\PSADT-WingetFW_<Version> with Toolkit\WinGetFW, the newest version of each
       detection script (Toolkit\Detection), Policies (ADMX/ADML), Mods\_Template.ps1 and links to the
       Console and mod file documentation.
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
    Version      : 1.2.0

    Release notes
    1.2.0  - Same layout as the 5.0.0 release zip: PSADT-WingetFW_<Version> with Toolkit\WinGetFW, the newest
             detection scripts, Policies, Mods\_Template.ps1 and documentation links.
    1.1.0  - The package is in Toolkit\WinGetFW (no version in the folder name).
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

$packageDir = Join-Path -Path $RepoRoot -ChildPath 'Toolkit\WinGetFW'
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
$stageDir = Join-Path -Path $OutputPath -ChildPath "PSADT-WingetFW_$Version"
if (Test-Path -LiteralPath $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force }
$toolkitDir = Join-Path -Path $stageDir -ChildPath 'Toolkit'
$detectionDir = Join-Path -Path $toolkitDir -ChildPath 'Detection'
$modsDir = Join-Path -Path $stageDir -ChildPath 'Mods'
$consoleDir = Join-Path -Path $stageDir -ChildPath 'Console'
$null = New-Item -Path $detectionDir, $modsDir, $consoleDir -ItemType Directory
Copy-Item -LiteralPath $packageDir -Destination $toolkitDir -Recurse

# Only the newest version of each detection script, for example wingetv2.0.2.ps1 and registryversionregexv.1.0.3.ps1
Get-ChildItem -LiteralPath (Join-Path -Path $RepoRoot -ChildPath 'Toolkit\Detection') -Filter '*.ps1' |
    Where-Object { $_.Name -match '^(.+?)v\.?(\d+\.\d+\.\d+)\.ps1$' } |
    Group-Object -Property { $_.Name -replace 'v\.?\d+\.\d+\.\d+\.ps1$' } |
    ForEach-Object { $_.Group | Sort-Object -Property { [version]($_.Name -replace '^.+?v\.?(\d+\.\d+\.\d+)\.ps1$', '$1') } | Select-Object -Last 1 } |
    Copy-Item -Destination $detectionDir

Copy-Item -LiteralPath (Join-Path -Path $RepoRoot -ChildPath 'Policies') -Destination $stageDir -Recurse
Copy-Item -LiteralPath (Join-Path -Path $packageDir -ChildPath 'Mods\_Template.ps1') -Destination $modsDir
$docs = 'https://github.com/ksk-itdk/PSADT-WingetFW/blob/main/Docs'
Set-Content -LiteralPath (Join-Path -Path $consoleDir -ChildPath 'WingetFW Console documentation.url') -Value @('[InternetShortcut]', "URL=$docs/Console.md") -Encoding ASCII
Set-Content -LiteralPath (Join-Path -Path $modsDir -ChildPath 'WingetFW mod files documentation.url') -Value @('[InternetShortcut]', "URL=$docs/Mods.md") -Encoding ASCII
[IO.File]::WriteAllText((Join-Path -Path $OutputPath -ChildPath 'release-notes.md'), $notes.Trim() + "`n", (New-Object -TypeName Text.UTF8Encoding -ArgumentList $false))

Write-Output $stageDir
