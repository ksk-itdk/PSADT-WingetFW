<#
.SYNOPSIS
    Pester tests for WingetFW.Console: command line builder, command line reader, detection scripts, manifest data.

.DESCRIPTION
    The builder is also checked against the command lines of the last VM test run (Tests\results\WingetFW-TestResults.json):
    every command that passed on the VM is accepted, every validation test (V, N) is rejected with the
    message WingetFW logged. Needs PowerShell 7.4 or later; skipped in Windows PowerShell 5.1.

.NOTES
    Maintained by: KSKITDK
    Version      : 1.1.0

    Release notes
    1.1.0  - Intune publish tests with mocked Graph calls (phase CON-2).
    1.0.1  - The VM command tests are not created when the list is empty (Windows PowerShell 5.1 failed in
             Pester discovery on an empty -ForEach).
    1.0.0  - First version (phase CON-1).

.LINK
    https://github.com/ksk-itdk/PSADT-WingetFW
#>

BeforeDiscovery {
    $skip = $PSVersionTable.PSVersion -lt [version]'7.4'
    $vmTests = @()
    $resultsFile = Join-Path -Path $PSScriptRoot -ChildPath '..\results\WingetFW-TestResults.json'
    if (-not $skip -and (Test-Path -LiteralPath $resultsFile))
    {
        $vmTests = @((Get-Content -LiteralPath $resultsFile -Raw | ConvertFrom-Json).Tests |
            # Q tests pass a raw command line on purpose (double quotes, unquoted GUID)
            Where-Object { $_.Result -eq 'PASS' -and $_.Id -notmatch '^Q' } |
            ForEach-Object {
                @{
                    Id        = $_.Id
                    Command   = $_.Command
                    Invalid   = $_.Id -match '^[VN]\d'
                    LogChecks = @($_.Checks | Where-Object { $_.Text -like 'toolkit log contains: *' } | ForEach-Object { $_.Text.Substring(22) })
                }
            })
    }
}

BeforeAll {
    if ($PSVersionTable.PSVersion -lt [version]'7.4') { return }
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\..\Console\WingetFW.Console\WingetFW.Console.psd1') -Force
    $map = Import-PowerShellDataFile -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..\Tools\WingetFW-ParameterMap.psd1')
}

Describe 'Get-WingetFWPackageInfo' -Skip:$skip {
    It 'reads the parameters of the newest package with their accepted values' {
        $info = Get-WingetFWPackageInfo
        $info.Version | Should -Match '^\d+\.\d+\.\d+$'
        $info.Parameters['scope'].Values | Should -Be @('User', 'Machine')
        $info.Parameters['exact'].Type | Should -Be 'Switch'
        $info.Parameters['id'].Type | Should -Be 'String'
    }

    It 'has the same parameters and types as WingetFW-ParameterMap.psd1' {
        $info = Get-WingetFWPackageInfo
        @($info.Parameters.Keys | Sort-Object) | Should -Be @($map.Parameters.Keys | Sort-Object)
        foreach ($name in $map.Parameters.Keys) { $info.Parameters[$name].Type | Should -Be $map.Parameters[$name] -Because "-$name" }
    }
}

Describe 'New-WingetFWCommandLine' -Skip:$skip {
    It 'writes values in single quotes and switches without a value' {
        $result = New-WingetFWCommandLine -Parameters ([ordered]@{ id = 'Postman.Postman'; exact = $true; Mode = 'User' })
        $result.CommandLine | Should -Be "Invoke-AppDeployToolkit.exe -DeploymentType 'Install' -id 'Postman.Postman' -exact -Mode 'User'"
        $result.Errors | Should -BeNullOrEmpty
    }

    It 'doubles single quotes and keeps spaces and braces inside the quotes' {
        $result = New-WingetFWCommandLine -Parameters ([ordered]@{ DeploymentType = 'Uninstall'; productcode = '{23170F69-40C1-2702-2604-000001000000}'; log = "C:\it's my log.txt" })
        $result.CommandLine | Should -Be "Invoke-AppDeployToolkit.exe -DeploymentType 'Uninstall' -productcode '{23170F69-40C1-2702-2604-000001000000}' -log 'C:\it''s my log.txt'"
    }

    It 'puts DeploymentType and Action first' {
        $result = New-WingetFWCommandLine -Parameters ([ordered]@{ id = '7zip.7zip'; Action = 'upgrade'; DeploymentType = 'Install' })
        $result.CommandLine | Should -Be "Invoke-AppDeployToolkit.exe -DeploymentType 'Install' -Action 'upgrade' -id '7zip.7zip'"
        $result.Action | Should -Be 'upgrade'
    }

    It 'leaves out switches set to false and empty values' {
        $result = New-WingetFWCommandLine -Parameters ([ordered]@{ id = 'a.b'; exact = $false; silent = [switch]$false; version = ''; log = '  ' })
        $result.CommandLine | Should -Be "Invoke-AppDeployToolkit.exe -DeploymentType 'Install' -id 'a.b'"
    }

    It 'uses the casing of the package for accepted values' {
        $result = New-WingetFWCommandLine -Parameters ([ordered]@{ id = 'a.b'; scope = 'machine'; architecture = 'x64'; installertype = 'wix'; action = 'UPGRADE' })
        $result.Parameters['scope'] | Should -BeExactly 'Machine'
        $result.Parameters['architecture'] | Should -BeExactly 'X64'
        $result.Parameters['installertype'] | Should -BeExactly 'Wix'
        $result.Parameters['Action'] | Should -BeExactly 'upgrade'
    }

    It 'reports a value that is not accepted' {
        (New-WingetFWCommandLine -Parameters @{ id = 'a.b'; scope = 'Everyone' }).Errors | Should -Contain "-scope 'Everyone' is not one of: User, Machine"
    }

    It 'reports an unknown parameter' {
        (New-WingetFWCommandLine -Parameters @{ id = 'a.b'; WingetID = 'x' }).Errors | Should -Contain 'Unknown parameter -WingetID'
    }

    It 'reports <Names> used together' -ForEach @(
        @{ Names = @('id', 'name') }
        @{ Names = @('interactive', 'override') }
        @{ Names = @('proxy', 'noproxy') }
        @{ Names = @('purge', 'preserve'); DeploymentType = 'Uninstall' }
    ) {
        $parameters = [ordered]@{ DeploymentType = $(if ($DeploymentType) { $DeploymentType } else { 'Install' }) }
        if ('id' -notin $Names) { $parameters['id'] = 'a.b' }
        foreach ($name in $Names) { $parameters[$name] = if ((Get-WingetFWPackageInfo).Parameters[$name].Type -eq 'Switch') { $true } else { 'x' } }
        (New-WingetFWCommandLine -Parameters $parameters).Errors -join "`n" | Should -Match "-$($Names -join ' and -') cannot be used together"
    }

    It 'reports -header without -source' {
        (New-WingetFWCommandLine -Parameters @{ id = 'a.b'; header = 'X: 1' }).Errors | Should -Contain '-header requires -source'
        (New-WingetFWCommandLine -Parameters @{ id = 'a.b'; header = 'X: 1'; source = 'rest' }).Errors | Should -BeNullOrEmpty
    }

    It 'reports an option the winget action does not support' {
        (New-WingetFWCommandLine -Parameters @{ DeploymentType = 'Uninstall'; id = 'a.b'; override = '/S' }).Errors -join "`n" | Should -Match '^-override is not an option with winget uninstall\. Allowed: -wingetmanifest, -id'
    }

    It 'reports a missing package (69001)' {
        (New-WingetFWCommandLine -Parameters @{ silent = $true }).Errors -join "`n" | Should -Match 'No package specified.*69001'
    }

    It 'checks ForceRepair against the install options' {
        $result = New-WingetFWCommandLine -Parameters ([ordered]@{ DeploymentType = 'Repair'; ForceRepair = $true; id = 'a.b'; custom = 'X=1' })
        $result.Action | Should -Be 'install'
        $result.Errors | Should -BeNullOrEmpty
        (New-WingetFWCommandLine -Parameters @{ ForceRepair = $true; id = 'a.b' }).Warnings | Should -Contain '-ForceRepair is ignored unless -DeploymentType is Repair'
    }

    It 'warns about double quotes in a value' {
        (New-WingetFWCommandLine -Parameters @{ id = 'a.b'; custom = '/DIR="C:\x"' }).Warnings -join "`n" | Should -Match '-custom contains double quotes'
    }

    It 'warns about -Mode User with -scope Machine' {
        (New-WingetFWCommandLine -Parameters @{ id = 'a.b'; Mode = 'User'; scope = 'Machine' }).Warnings -join "`n" | Should -Match 'Mode User'
    }

    It '-Uninstall leaves out Action, version and the options uninstall does not support' {
        $install = New-WingetFWCommandLine -Parameters ([ordered]@{ Action = 'upgrade'; Mode = 'User'; id = 'a.b'; exact = $true; version = '1.0'; scope = 'User'; architecture = 'X64'; custom = 'X=1'; silent = $true; OverrideAPPName = 'App' })
        $uninstall = New-WingetFWCommandLine -Parameters $install.Parameters -Uninstall
        $uninstall.CommandLine | Should -Be "Invoke-AppDeployToolkit.exe -DeploymentType 'Uninstall' -Mode 'User' -id 'a.b' -exact -scope 'User' -silent -OverrideAPPName 'App'"
        @($uninstall.Dropped) | Should -Be @('-Action', '-version', '-architecture', '-custom')
        $uninstall.Errors | Should -BeNullOrEmpty
    }
}

Describe 'ConvertFrom-WingetFWCommandLine' -Skip:$skip {
    It 'reads back what New-WingetFWCommandLine writes' {
        $built = New-WingetFWCommandLine -Parameters ([ordered]@{ id = '7zip.7zip'; exact = $true; log = "C:\it's my log.txt"; custom = 'A=1 B="2"'; productcode = '{GUID}'; DeploymentType = 'Repair' })
        $read = ConvertFrom-WingetFWCommandLine -CommandLine $built.CommandLine
        $read.Errors | Should -BeNullOrEmpty
        $read.Exe | Should -Be 'Invoke-AppDeployToolkit.exe'
        @($read.Parameters.Keys) | Should -Be @($built.Parameters.Keys)
        foreach ($name in $built.Parameters.Keys) { $read.Parameters[$name] | Should -Be $built.Parameters[$name] }
    }

    It 'reads a quoted exe path and only arguments' {
        (ConvertFrom-WingetFWCommandLine -CommandLine '"C:\My Apps\Invoke-AppDeployToolkit.exe" -id x.y').Exe | Should -Be '"C:\My Apps\Invoke-AppDeployToolkit.exe"'
        $read = ConvertFrom-WingetFWCommandLine -CommandLine "-skipdependencies -locale 'en-US'"
        $read.Exe | Should -Be ''
        $read.Parameters['skipdependencies'] | Should -BeTrue
        $read.Parameters['locale'] | Should -Be 'en-US'
    }

    It 'reports an unquoted GUID and a double-quoted value with spaces' {
        $read = ConvertFrom-WingetFWCommandLine -CommandLine 'Invoke-AppDeployToolkit.exe -productcode {ABC} -name "7 Zip"'
        $read.Errors -join "`n" | Should -Match 'productcode value \{ABC\} is not quoted'
        $read.Errors -join "`n" | Should -Match '-name value is in double quotes and has spaces'
        $read.Parameters['productcode'] | Should -Be '{ABC}'
    }

    It 'reads -switch:$false and reports a missing value and an unknown parameter' {
        $read = ConvertFrom-WingetFWCommandLine -CommandLine '-exact:$false -id -silent -foo 1'
        $read.Parameters['exact'] | Should -BeFalse
        $read.Errors | Should -Contain '-id has no value'
        $read.Errors | Should -Contain 'Unknown parameter -foo'
    }
}

Describe 'Command lines of the last VM test run' -Skip:$skip {
    # Pester fails discovery on an empty -ForEach (Windows PowerShell 5.1 or no results file)
    if (-not $vmTests.Count) { return }
    It '<Id>: same rule result as WingetFW on the VM' -ForEach $vmTests {
        $read = ConvertFrom-WingetFWCommandLine -CommandLine $Command
        $read.Errors | Should -BeNullOrEmpty
        $built = New-WingetFWCommandLine -Parameters $read.Parameters
        if ($Invalid)
        {
            $built.Errors | Should -Not -BeNullOrEmpty
            foreach ($pattern in $LogChecks) { $built.Errors -join "`n" | Should -Match $pattern }
        }
        else
        {
            $built.Errors | Should -BeNullOrEmpty
        }
        # The built command has the same parameters and values as the one that ran on the VM
        $again = ConvertFrom-WingetFWCommandLine -CommandLine $built.CommandLine
        $again.Errors | Should -BeNullOrEmpty
        @($again.Parameters.Keys | Sort-Object) | Should -Be @($read.Parameters.Keys | Sort-Object)
        foreach ($name in $read.Parameters.Keys) { $again.Parameters[$name] | Should -Be $read.Parameters[$name] -Because "-$name" }
    }
}

Describe 'New-WingetFWDetectionScript' -Skip:$skip {
    BeforeAll {
        $readAssignments = {
            param ([string]$Text)
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$parseErrors)
            $parseErrors | Should -BeNullOrEmpty
            $values = @{}
            foreach ($assignment in $ast.FindAll({ param ($a) $a -is [System.Management.Automation.Language.AssignmentStatementAst] -and $a.Parent.Parent -eq $ast }, $true))
            {
                $isString = $assignment.Right.Expression -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $assignment.Right.Expression -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
                if ($assignment.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $isString)
                {
                    $values[$assignment.Left.VariablePath.UserPath] = & ([scriptblock]::Create($assignment.Right.Extent.Text))
                }
            }
            $values
        }
    }

    It 'fills in the newest winget template' {
        $result = New-WingetFWDetectionScript -Type Winget -Id 'Postman.Postman'
        $newest = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..\Toolkit\Detection\wingetv*.ps1') | Sort-Object -Property { [version]($_.BaseName -replace '^wingetv', '') } | Select-Object -Last 1
        $result.Template | Should -Be $newest.Name
        (& $readAssignments $result.Text)['app'] | Should -BeExactly 'Postman.Postman'
        # Only the assignment changes; the example in the help keeps its value
        $original = Get-Content -LiteralPath $newest.FullName -Raw
        ($result.Text -split "`r?`n").Count | Should -Be ($original -split "`r?`n").Count
        @(Compare-Object -ReferenceObject ($original -split "`r?`n") -DifferenceObject ($result.Text -split "`r?`n")).Count | Should -Be 2
    }

    It 'escapes $, double quotes and backticks in the registry template' {
        $result = New-WingetFWDetectionScript -Type Registry -AppName 'Note"pad$++ `x*' -AppVersion '8.1'
        $result.Template | Should -Match '^registryversionregexv\.\d+\.\d+\.\d+\.ps1$'
        $values = & $readAssignments $result.Text
        $values['AppName'] | Should -BeExactly 'Note"pad$++ `x*'
        $values['AppVersion'] | Should -BeExactly '8.1'
    }

    It 'saves the script with the encoding of the template' {
        $path = Join-Path -Path $TestDrive -ChildPath 'detect.ps1'
        $result = New-WingetFWDetectionScript -Type Winget -Id '7zip.7zip' -Path $path
        [System.IO.File]::ReadAllText($path) | Should -BeExactly $result.Text
    }

    It 'rejects an ID with spaces' {
        { New-WingetFWDetectionScript -Type Winget -Id '7zip 7zip' } | Should -Throw '*spaces*'
    }
}

Describe 'Manifest data' -Skip:$skip {
    It 'merges the root installer fields into each installer; installer fields win' {
        InModuleScope -ModuleName 'WingetFW.Console' {
            $versionData = @{ PackageIdentifier = 'Contoso.App'; PackageVersion = '1.10' }
            $localeData = @{ PackageName = 'Contoso App'; Publisher = 'Contoso'; License = 'MIT'; Tags = @('a', 'b') }
            $installerData = @{
                Scope = 'machine'; InstallerType = 'exe'; ReleaseDate = [datetime]'2026-10-01'
                InstallerSwitches = @{ Silent = '/S'; Custom = '/NORESTART' }
                Dependencies = @{ PackageDependencies = @(@{ PackageIdentifier = 'Microsoft.VCRedist.2015+.x64'; MinimumVersion = '14.0' }) }
                Installers = @(
                    @{ Architecture = 'x64'; InstallerSwitches = @{ Silent = '/quiet' } }
                    @{ Architecture = 'x86'; InstallerType = 'wix'; Scope = 'user'; ProductCode = '{P}'; AppsAndFeaturesEntries = @(@{ DisplayName = 'Contoso App (x86)'; DisplayVersion = '1.10.0' }) }
                )
            }
            $manifest = ConvertFrom-WingetFWManifestData -VersionData $versionData -InstallerData $installerData -LocaleData $localeData
            $manifest.Name | Should -Be 'Contoso App'
            $manifest.Dependencies | Should -Be @('Microsoft.VCRedist.2015+.x64 (>= 14.0)')
            $manifest.Installers.Count | Should -Be 2
            $x64, $x86 = $manifest.Installers
            $x64.InstallerType | Should -Be 'exe'
            $x64.Scope | Should -Be 'machine'
            $x64.Silent | Should -Be '/quiet'
            $x64.Custom | Should -Be '/NORESTART'
            $x64.ReleaseDate | Should -Be '2026-10-01'
            $x86.InstallerType | Should -Be 'wix'
            $x86.Scope | Should -Be 'user'
            $x86.ProductCode | Should -Be '{P}'
            $x86.DisplayName | Should -Be 'Contoso App (x86)'
        }
    }
}

Describe 'Intune publish (Graph mocked)' -Skip:$skip {
    It 'builds the Win32 app body with return codes, detection script and requirements' {
        InModuleScope -ModuleName 'WingetFW.Console' {
            $script = "`$app = `"B$([char]0xFC)ro`""
            $body = New-WingetFWIntuneAppBody -DisplayName '7-Zip' -Publisher 'Igor Pavlov' -Notes 'WingetFW 5.0.0' -FileName 'x.intunewin' -SetupFile 'Invoke-AppDeployToolkit.exe' `
                -InstallCommandLine 'i' -UninstallCommandLine 'u' -RunAsAccount 'user' -DetectionScript $script -AllowedArchitectures 'x64' -MinimumWindowsRelease '1809'
            $body['@odata.type'] | Should -Be '#microsoft.graph.win32LobApp'
            $body.description | Should -Be '7-Zip'
            $body.informationUrl | Should -BeNullOrEmpty
            $body.installExperience.runAsAccount | Should -Be 'user'
            $body.applicableArchitectures | Should -Be 'none'
            $body.allowedArchitectures | Should -Be 'x64'
            @($body.returnCodes | Where-Object { $_.returnCode -eq 69002 }).type | Should -Be 'retry'
            @($body.returnCodes).returnCode | Should -Be @(0, 1707, 3010, 1641, 1618, 69002)
            $bytes = [Convert]::FromBase64String($body.rules[0].scriptContent)
            $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
            [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3) | Should -BeExactly $script
            $body.rules[0].ruleType | Should -Be 'detection'
        }
    }

    It 'builds group assignments' {
        InModuleScope -ModuleName 'WingetFW.Console' {
            $body = New-WingetFWAssignmentBody -Assignments @([pscustomobject]@{ GroupId = 'g1'; Intent = 'available' })
            $body.mobileAppAssignments.Count | Should -Be 1
            $body.mobileAppAssignments[0].intent | Should -Be 'available'
            $body.mobileAppAssignments[0].target['@odata.type'] | Should -Be '#microsoft.graph.groupAssignmentTarget'
            $body.mobileAppAssignments[0].target.groupId | Should -Be 'g1'
        }
    }

    It 'reads a .intunewin file' {
        $file = Join-Path -Path $TestDrive -ChildPath 'test.intunewin'
        $zip = [System.IO.Compression.ZipFile]::Open($file, 'Create')
        $xml = '<ApplicationInfo><FileName>IntunePackage.intunewin</FileName><SetupFile>Invoke-AppDeployToolkit.exe</SetupFile><UnencryptedContentSize>5</UnencryptedContentSize>' +
            '<EncryptionInfo><EncryptionKey>k</EncryptionKey><MacKey>m</MacKey><InitializationVector>iv</InitializationVector><Mac>mac</Mac><ProfileIdentifier>ProfileVersion1</ProfileIdentifier><FileDigest>d</FileDigest><FileDigestAlgorithm>SHA256</FileDigestAlgorithm></EncryptionInfo></ApplicationInfo>'
        foreach ($entry in @(@{ Name = 'IntuneWinPackage/Metadata/Detection.xml'; Text = $xml }, @{ Name = 'IntuneWinPackage/Contents/IntunePackage.intunewin'; Text = '1234567' }))
        {
            $writer = [System.IO.StreamWriter]::new($zip.CreateEntry($entry.Name).Open())
            $writer.Write($entry.Text)
            $writer.Close()
        }
        $zip.Dispose()

        $package = Get-WingetFWIntuneWinPackage $file
        try
        {
            $package.SetupFile | Should -Be 'Invoke-AppDeployToolkit.exe'
            $package.UnencryptedSize | Should -Be 5
            $package.EncryptedSize | Should -Be 7
            $package.EncryptionInfo.fileDigestAlgorithm | Should -Be 'SHA256'
        }
        finally { Remove-Item -LiteralPath $package.EncryptedFile }
    }

    Context 'New-WingetFWIntuneApp' {
        BeforeAll {
            $assignment = [pscustomobject]@{ GroupId = '11111111-2222-3333-4444-555555555555'; Intent = 'required' }
            $appParams = @{
                DisplayName = '7-Zip'; Publisher = 'Igor Pavlov'; InstallCommandLine = 'i'; UninstallCommandLine = 'u'
                DetectionScript = 'x'; IntuneWinFile = 'C:\fake\Invoke-AppDeployToolkit.intunewin'
            }
        }

        BeforeEach {
            $script:calls = [System.Collections.Generic.List[object]]::new()
            Mock -ModuleName 'WingetFW.Console' Get-WingetFWIntuneWinPackage { [pscustomobject]@{ SetupFile = 'Invoke-AppDeployToolkit.exe'; EncryptedFile = 'C:\fake\none.bin' } }
            Mock -ModuleName 'WingetFW.Console' Publish-WingetFWIntuneWinContent { '1' }
            Mock -ModuleName 'WingetFW.Console' Start-Sleep { }
            Mock -ModuleName 'WingetFW.Console' Invoke-WingetFWGraph {
                $script:calls.Add([pscustomobject]@{ Method = $Method; Uri = $Uri; Body = $Body })
                if ($Method -eq 'POST' -and $Uri -match '/mobileApps$') { return [pscustomobject]@{ id = 'app-1' } }
                if ($Method -eq 'GET') { return [pscustomobject]@{ publishingState = 'published' } }
            }
        }

        It 'creates the app, commits the content and assigns it' {
            $result = New-WingetFWIntuneApp @appParams -Assignments @($assignment) -WingetFWVersion '5.0.0'
            $result.Id | Should -Be 'app-1'
            $result.ContentVersion | Should -Be '1'
            @($script:calls | ForEach-Object { "$($_.Method) $($_.Uri -replace '^.*/mobileApps', '')" }) | Should -Be @('POST ', 'PATCH /app-1', 'GET /app-1', 'POST /app-1/assign')
            $script:calls[0].Body.notes | Should -Be 'WingetFW 5.0.0'
            $script:calls[0].Body.fileName | Should -Be 'Invoke-AppDeployToolkit.intunewin'
            $script:calls[1].Body.committedContentVersion | Should -Be '1'
            $script:calls[3].Body.mobileAppAssignments[0].target.groupId | Should -Be $assignment.GroupId
        }

        It 'does not assign without assignments' {
            $null = New-WingetFWIntuneApp @appParams
            @($script:calls | Where-Object { $_.Uri -like '*/assign' }).Count | Should -Be 0
        }

        It 'names the created app when the upload fails' {
            Mock -ModuleName 'WingetFW.Console' Publish-WingetFWIntuneWinContent { throw 'upload broke' }
            { New-WingetFWIntuneApp @appParams } | Should -Throw '*(ID app-1)*upload broke*'
        }

        It 'rejects a package with another setup file before calling Graph' {
            Mock -ModuleName 'WingetFW.Console' Get-WingetFWIntuneWinPackage { [pscustomobject]@{ SetupFile = 'Deploy-Application.exe'; EncryptedFile = 'C:\fake\none.bin' } }
            { New-WingetFWIntuneApp @appParams } | Should -Throw '*expected Invoke-AppDeployToolkit.exe*'
            $script:calls.Count | Should -Be 0
        }

        It 'rejects a wrong intent or group ID' {
            { New-WingetFWIntuneApp @appParams -Assignments @([pscustomobject]@{ GroupId = $assignment.GroupId; Intent = 'optional' }) } | Should -Throw '*must be required, available or uninstall*'
            { New-WingetFWIntuneApp @appParams -Assignments @([pscustomobject]@{ GroupId = 'x'; Intent = 'required' }) } | Should -Throw '*is not a GUID*'
            $script:calls.Count | Should -Be 0
        }
    }

    It 'escapes quotes in the group search' {
        Mock -ModuleName 'WingetFW.Console' Invoke-WingetFWGraph { $script:groupUri = $Uri; [pscustomobject]@{ value = @([pscustomobject]@{ id = 'g'; displayName = "O'Brien team"; description = '' }) } }
        $groups = @(Find-WingetFWGroup -Name "O'Brien")
        $groups[0].DisplayName | Should -Be "O'Brien team"
        [uri]::UnescapeDataString($script:groupUri) | Should -Match "startswith\(displayName,'O''Brien'\)"
    }
}
