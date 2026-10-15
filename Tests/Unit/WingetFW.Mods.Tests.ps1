<#
.SYNOPSIS
    Pester tests for the mod functions in WingetFW.Core (Import-WingetFWMod, Invoke-WingetFWModSection).

.DESCRIPTION
    Uses a package folder and cache in TestDrive and empty policy/local keys in TestRegistry.
    Azure blob URLs are simulated with a mocked Invoke-WebRequest.

.NOTES
    Maintained by: KSKITDK
    Version      : 1.0.0

    Release notes
    1.0.0  - First version (phase FW-3).

.LINK
    https://github.com/ksk-itdk/PSADT-WingetFW
#>

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\..\Source\WingetFW.Core\WingetFW.Core.psd1') -Force

    function New-ModFile
    {
        param ([string]$Path, [string]$Content)
        $folder = Split-Path -Path $Path -Parent
        if (-not (Test-Path -LiteralPath $folder)) { $null = New-Item -Path $folder -ItemType Directory -Force }
        Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
    }

    $validApp = @'
$Settings = @{
    Install = @{ Custom = 'REBOOT=ReallySuppress'; Scope = 'Machine' }
}
function PreInstall { Add-Content -LiteralPath $WingetFW.Trace -Value "app PreInstall $($WingetFW.Id)" }
function PostInstall { Add-Content -LiteralPath $WingetFW.Trace -Value "app PostInstall $($WingetFW.ExitCode)" }
function PreUninstall { $false }
'@
    $validGlobal = @'
function PreInstall { Add-Content -LiteralPath $WingetFW.Trace -Value 'global PreInstall' }
'@
}

AfterAll {
    Remove-Module -Name 'WingetFW.Core' -Force -ErrorAction SilentlyContinue
}

Describe 'Import-WingetFWMod' {
    BeforeEach {
        Mock -ModuleName 'WingetFW.Core' -CommandName 'Write-WingetFWLog' -MockWith { }
        $package = Join-Path -Path $TestDrive -ChildPath ('pkg' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $null = New-Item -Path (Join-Path -Path $package -ChildPath 'Mods') -ItemType Directory -Force
        $cache = Join-Path -Path $TestDrive -ChildPath ('cache' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        foreach ($path in @('TestRegistry:\Policy', 'TestRegistry:\Local'))
        {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            $null = New-Item -Path $path -Force
        }
        $common = @{ PackagePath = $package; CacheRoot = $cache; PolicyPath = 'TestRegistry:\Policy'; LocalPath = 'TestRegistry:\Local' }
    }

    It 'Returns no mods when there are no files' {
        $mods = Import-WingetFWMod -Id '7zip.7zip' @common
        $mods.Global | Should -BeNullOrEmpty
        $mods.App | Should -BeNullOrEmpty
    }

    It 'Loads the global and the app mod from the package Mods folder' {
        New-ModFile -Path "$package\Mods\_WingetFW.ps1" -Content $validGlobal
        New-ModFile -Path "$package\Mods\winget\7zip.7zip.ps1" -Content $validApp
        $mods = Import-WingetFWMod -Id '7zip.7zip' @common
        $mods.Global.Functions | Should -Be @('PreInstall')
        $mods.App.Functions | Should -Be @('PreInstall', 'PostInstall', 'PreUninstall')
        $mods.App.Settings.Install.Custom | Should -Be 'REBOOT=ReallySuppress'
        $mods.App.Origin | Should -Be "$package\Mods\winget\7zip.7zip.ps1"
    }

    It 'Only loads the global mod without an ID' {
        New-ModFile -Path "$package\Mods\_WingetFW.ps1" -Content $validGlobal
        New-ModFile -Path "$package\Mods\winget\7zip.7zip.ps1" -Content $validApp
        $mods = Import-WingetFWMod -Id '' @common
        $mods.Global | Should -Not -BeNullOrEmpty
        $mods.App | Should -BeNullOrEmpty
    }

    It 'Uses the source as the folder of the app mod' {
        New-ModFile -Path "$package\Mods\msstore\9NBLGGH4NNS1.ps1" -Content $validApp
        (Import-WingetFWMod -Id '9NBLGGH4NNS1' -Source 'msstore' @common).App | Should -Not -BeNullOrEmpty
    }

    It 'Accepts the shipped template (Mods\_Template.ps1) with all 16 sections' {
        $template = Get-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..\Toolkit\WinGetFW5.0.0\Mods\_Template.ps1') -Raw
        New-ModFile -Path "$package\Mods\winget\7zip.7zip.ps1" -Content $template
        $mods = Import-WingetFWMod -Id '7zip.7zip' @common
        $mods.App.Functions.Count | Should -Be 16
        $mods.App.Settings.Keys | Sort-Object | Should -Be @('Install', 'Repair', 'Uninstall', 'Upgrade')
    }

    It 'Refuses <Case>' -ForEach @(
        @{ Case = 'code at the top level'; Content = "Write-Output 'runs at load'`nfunction PreInstall { }"; Message = '*runs code when the file is loaded*' }
        @{ Case = 'a second $Settings'; Content = "`$Settings = @{}`n`$Settings = @{}"; Message = '*runs code when the file is loaded*' }
        @{ Case = 'another variable'; Content = "`$x = 1"; Message = '*runs code when the file is loaded*' }
        @{ Case = '$Settings with code'; Content = "`$Settings = @{ Install = @{ Custom = (Get-Date) } }"; Message = '*may only contain fixed values*' }
        @{ Case = 'a param block'; Content = "param(`$a)`nfunction PreInstall { }"; Message = '*only function definitions*' }
        @{ Case = 'a using statement'; Content = "using namespace System.IO`nfunction PreInstall { }"; Message = '*only function definitions*' }
        @{ Case = 'a syntax error'; Content = 'function PreInstall { '; Message = '*syntax error*' }
    ) {
        New-ModFile -Path "$package\Mods\winget\7zip.7zip.ps1" -Content $Content
        { Import-WingetFWMod -Id '7zip.7zip' @common } | Should -Throw $Message
    }

    It 'Refuses an ID with path characters' {
        { Import-WingetFWMod -Id '..\..\evil' @common } | Should -Throw '*mod file name*'
    }

    It 'Refuses a ScriptRoot that is not in AllowedScriptSources' {
        $other = Join-Path -Path $TestDrive -ChildPath 'other'
        $null = New-Item -Path $other -ItemType Directory -Force
        $null = New-ItemProperty -Path 'TestRegistry:\Policy' -Name 'ScriptRoot' -Value $other
        { Import-WingetFWMod -Id '7zip.7zip' @common } | Should -Throw '*is not in AllowedScriptSources*'
    }

    It 'Refuses a ScriptRoot that leaves an allowed folder with ..' {
        $null = New-ItemProperty -Path 'TestRegistry:\Policy' -Name 'ScriptRoot' -Value "$package\Mods\..\..\elsewhere"
        { Import-WingetFWMod -Id '7zip.7zip' @common } | Should -Throw '*is not in AllowedScriptSources*'
    }

    It 'Searches the ScriptRoots in order; the first one with a file wins' {
        $first = Join-Path -Path $TestDrive -ChildPath 'first'
        $second = Join-Path -Path $TestDrive -ChildPath 'second'
        New-ModFile -Path "$first\_WingetFW.ps1" -Content $validGlobal
        New-ModFile -Path "$second\_WingetFW.ps1" -Content 'function PostInstall { }'
        New-ModFile -Path "$second\winget\7zip.7zip.ps1" -Content $validApp
        $null = New-ItemProperty -Path 'TestRegistry:\Policy' -Name 'ScriptRoot' -Value @($first, $second) -PropertyType MultiString
        $null = New-ItemProperty -Path 'TestRegistry:\Policy' -Name 'AllowedScriptSources' -Value @($TestDrive) -PropertyType MultiString
        $mods = Import-WingetFWMod -Id '7zip.7zip' @common
        $mods.Global.Origin | Should -Be "$first\_WingetFW.ps1"
        $mods.App.Origin | Should -Be "$second\winget\7zip.7zip.ps1"
    }

    It 'OnDemand: removes the cached copy when the file is deleted from the ScriptRoot' {
        New-ModFile -Path "$package\Mods\winget\7zip.7zip.ps1" -Content $validApp
        $null = Import-WingetFWMod -Id '7zip.7zip' @common
        @(Get-ChildItem -LiteralPath $cache -Recurse -Filter '7zip.7zip.ps1').Count | Should -Be 1
        Remove-Item -LiteralPath "$package\Mods\winget\7zip.7zip.ps1"
        (Import-WingetFWMod -Id '7zip.7zip' @common).App | Should -BeNullOrEmpty
        @(Get-ChildItem -LiteralPath $cache -Recurse -Filter '7zip.7zip.ps1').Count | Should -Be 0
    }

    It 'OnDemand: throws when the ScriptRoot cannot be reached and UseCachedScriptsWhenOffline is off' {
        $root = Join-Path -Path $TestDrive -ChildPath 'offline'
        $null = New-ItemProperty -Path 'TestRegistry:\Policy' -Name 'ScriptRoot' -Value $root
        $null = New-ItemProperty -Path 'TestRegistry:\Policy' -Name 'AllowedScriptSources' -Value @($TestDrive) -PropertyType MultiString
        { Import-WingetFWMod -Id '7zip.7zip' @common } | Should -Throw "*can't be reached*"
    }

    It 'OnDemand: uses the cached copy when the ScriptRoot cannot be reached and UseCachedScriptsWhenOffline is on' {
        $root = Join-Path -Path $TestDrive -ChildPath 'goesoffline'
        New-ModFile -Path "$root\winget\7zip.7zip.ps1" -Content $validApp
        $null = New-ItemProperty -Path 'TestRegistry:\Policy' -Name 'ScriptRoot' -Value $root
        $null = New-ItemProperty -Path 'TestRegistry:\Policy' -Name 'AllowedScriptSources' -Value @($TestDrive) -PropertyType MultiString
        $null = Import-WingetFWMod -Id '7zip.7zip' @common
        Rename-Item -LiteralPath $root -NewName 'wentoffline'
        $null = New-ItemProperty -Path 'TestRegistry:\Policy' -Name 'UseCachedScriptsWhenOffline' -Value 1 -PropertyType DWord
        $mods = Import-WingetFWMod -Id '7zip.7zip' @common
        $mods.App.Origin | Should -BeLike '*(cached copy)'
    }

    It 'Mirror: copies the ScriptRoot to the cache and removes files that are gone' {
        New-ModFile -Path "$package\Mods\_WingetFW.ps1" -Content $validGlobal
        New-ModFile -Path "$package\Mods\winget\7zip.7zip.ps1" -Content $validApp
        New-ModFile -Path "$package\Mods\winget\jqlang.jq.ps1" -Content $validApp
        $null = New-ItemProperty -Path 'TestRegistry:\Policy' -Name 'ScriptSyncMode' -Value 'Mirror'
        $null = Import-WingetFWMod -Id '7zip.7zip' @common
        @(Get-ChildItem -LiteralPath $cache -Recurse -File).Count | Should -Be 3
        Remove-Item -LiteralPath "$package\Mods\winget\jqlang.jq.ps1"
        $mods = Import-WingetFWMod -Id '7zip.7zip' @common
        @(Get-ChildItem -LiteralPath $cache -Recurse -File).Count | Should -Be 2
        $mods.App | Should -Not -BeNullOrEmpty
    }

    It 'RequireSignedScripts Signed refuses an unsigned file' {
        New-ModFile -Path "$package\Mods\winget\7zip.7zip.ps1" -Content $validApp
        $null = New-ItemProperty -Path 'TestRegistry:\Policy' -Name 'RequireSignedScripts' -Value 'Signed'
        { Import-WingetFWMod -Id '7zip.7zip' @common } | Should -Throw '*is not validly signed (NotSigned)*'
    }

    It 'Refuses <Name> = <Value>' -ForEach @(
        @{ Name = 'ScriptSyncMode'; Value = 'Sometimes'; Message = '*ScriptSyncMode*not valid*' }
        @{ Name = 'RequireSignedScripts'; Value = 'Maybe'; Message = '*RequireSignedScripts*not valid*' }
        @{ Name = 'RequireSignedScripts'; Value = 'TrustedSigners'; Message = '*TrustedSigners is empty*' }
    ) {
        $null = New-ItemProperty -Path 'TestRegistry:\Policy' -Name $Name -Value $Value
        { Import-WingetFWMod -Id '7zip.7zip' @common } | Should -Throw $Message
    }

    Context 'Azure blob ScriptRoot (simulated)' {
        BeforeEach {
            $blobRoot = 'https://contoso.blob.core.windows.net/mods/prod?sv=2024&sp=rl&sig=SECRET'
            $null = New-ItemProperty -Path 'TestRegistry:\Policy' -Name 'ScriptRoot' -Value $blobRoot
            $null = New-ItemProperty -Path 'TestRegistry:\Policy' -Name 'AllowedScriptSources' -Value @('https://contoso.blob.core.windows.net/mods/') -PropertyType MultiString
            $script:blobs = @{ 'prod/_WingetFW.ps1' = $validGlobal; 'prod/winget/7zip.7zip.ps1' = $validApp }
            Mock -ModuleName 'WingetFW.Core' -CommandName 'Invoke-WebRequest' -MockWith {
                $requestUri = [Uri]$Uri
                if ($requestUri.Query -notmatch 'sig=SECRET') { throw 'SAS missing' }
                if ($requestUri.Query -match 'comp=list')
                {
                    $items = ($script:blobs.Keys | ForEach-Object { "<Blob><Name>$_</Name></Blob>" }) -join ''
                    return [pscustomobject]@{ Content = "<?xml version=`"1.0`" encoding=`"utf-8`"?><EnumerationResults><Blobs>$items</Blobs><NextMarker /></EnumerationResults>" }
                }
                $name = [Uri]::UnescapeDataString($requestUri.AbsolutePath.Substring('/mods/'.Length))
                if (-not $script:blobs.ContainsKey($name))
                {
                    $exception = New-Object -TypeName Exception -ArgumentList 'The remote server returned an error: (404) Not Found.'
                    $exception | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = 404 })
                    throw $exception
                }
                Set-Content -LiteralPath $OutFile -Value $script:blobs[$name] -Encoding UTF8
            }
        }

        It 'OnDemand: downloads the files with the SAS and masks the SAS in the origin' {
            $mods = Import-WingetFWMod -Id '7zip.7zip' @common
            $mods.App.Origin | Should -Be 'https://contoso.blob.core.windows.net/mods/prod/winget/7zip.7zip.ps1?sv=2024&sp=rl&sig=***'
            $mods.Global | Should -Not -BeNullOrEmpty
        }

        It 'OnDemand: a missing blob (404) means no mod' {
            (Import-WingetFWMod -Id 'jqlang.jq' @common).App | Should -BeNullOrEmpty
        }

        It 'Mirror: lists the container and downloads all .ps1 files' {
            $script:blobs['prod/winget/jqlang.jq.ps1'] = $validApp
            $null = New-ItemProperty -Path 'TestRegistry:\Policy' -Name 'ScriptSyncMode' -Value 'Mirror'
            $mods = Import-WingetFWMod -Id '7zip.7zip' @common
            $mods.App | Should -Not -BeNullOrEmpty
            @(Get-ChildItem -LiteralPath $cache -Recurse -File).Count | Should -Be 3
            Should -Invoke -ModuleName 'WingetFW.Core' -CommandName 'Invoke-WebRequest' -Times 1 -Exactly -ParameterFilter { $Uri -match 'restype=container&comp=list&prefix=prod%2F' }
        }

        It 'Mirror: skips blob names that leave the cache folder' {
            $script:blobs['prod/../evil.ps1'] = 'function PreInstall { }'
            $null = New-ItemProperty -Path 'TestRegistry:\Policy' -Name 'ScriptSyncMode' -Value 'Mirror'
            $null = Import-WingetFWMod -Id '7zip.7zip' @common
            Join-Path -Path $cache -ChildPath 'evil.ps1' | Should -Not -Exist
        }
    }
}

Describe 'Invoke-WingetFWModSection' {
    BeforeAll {
        Mock -ModuleName 'WingetFW.Core' -CommandName 'Write-WingetFWLog' -MockWith { }
        $package = Join-Path -Path $TestDrive -ChildPath 'pkg'
        New-ModFile -Path "$package\Mods\winget\7zip.7zip.ps1" -Content $validApp
        foreach ($path in @('TestRegistry:\Policy', 'TestRegistry:\Local')) { $null = New-Item -Path $path -Force }
        $mods = Import-WingetFWMod -Id '7zip.7zip' -PackagePath $package -CacheRoot (Join-Path -Path $TestDrive -ChildPath 'cache') -PolicyPath 'TestRegistry:\Policy' -LocalPath 'TestRegistry:\Local'
        $trace = Join-Path -Path $TestDrive -ChildPath 'trace.txt'
        $context = [pscustomobject]@{ Id = '7zip.7zip'; ExitCode = 0; Trace = $trace }
    }

    It 'Runs a section with $WingetFW as the context and returns $true' {
        Invoke-WingetFWModSection -Mod $mods.App -Section 'PreInstall' -Context $context | Should -BeTrue
        Get-Content -LiteralPath $trace | Should -Contain 'app PreInstall 7zip.7zip'
    }

    It 'Returns $false when the section returns $false' {
        Invoke-WingetFWModSection -Mod $mods.App -Section 'PreUninstall' -Context $context | Should -BeFalse
    }

    It 'Returns nothing when the mod has no such section' {
        Invoke-WingetFWModSection -Mod $mods.App -Section 'NotInstalled' -Context $context | Should -BeNullOrEmpty
    }

    It 'Does not leave mod functions in the caller session' {
        Get-Command -Name 'PreInstall' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
}
