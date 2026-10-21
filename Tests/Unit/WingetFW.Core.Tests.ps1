#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

<#
.SYNOPSIS
    Pester tests for WingetFW.Core (settings, logging, event log, state files).

.DESCRIPTION
    Runs in Windows PowerShell 5.1 and PowerShell 7. Tests marked [admin] are skipped without administrator rights.
    Registry tests use the Pester TestRegistry drive, file tests use TestDrive.

.NOTES
    Maintained by: KSKITDK
    Version      : 1.1.0

    Release notes
    1.1.0  - ADMX list keys (ordered list, name/value table), empty list key, -AsBoolean.
    1.0.0  - First version.

.LINK
    https://github.com/ksk-itdk/PSADT-WingetFW
#>

BeforeDiscovery {
    $principal = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    $levelNames = @('Policy', 'CommandLine', 'Mod', 'Local', 'Config', 'Default')
    $settingCases = foreach ($mask in 0..63)
    {
        $present = @(for ($i = 0; $i -lt $levelNames.Count; $i++) { if ($mask -band (1 -shl $i)) { $levelNames[$i] } })
        @{
            Present  = $present
            Expected = $(if ($present.Count) { $present[0] } else { 'None' })
            Label    = $(if ($present.Count) { $present -join '+' } else { 'nothing set' })
        }
    }
}

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\Source\WingetFW.Core\WingetFW.Core.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name 'WingetFW.Core' -Force -ErrorAction SilentlyContinue
}

Describe 'Get-WingetFWSetting' {
    BeforeAll {
        Mock -ModuleName 'WingetFW.Core' -CommandName 'Write-WingetFWLog' -MockWith { }
        $policyPath = 'TestRegistry:\Policy'
        $localPath = 'TestRegistry:\Local'
    }

    BeforeEach {
        foreach ($path in @($policyPath, $localPath))
        {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            $null = New-Item -Path $path -Force
        }
    }

    It 'Levels set: <Label> -> source <Expected>' -ForEach $settingCases {
        $params = @{ Name = 'TestSetting'; PolicyPath = $policyPath; LocalPath = $localPath; CommandLine = @{}; ModSettings = @{}; Config = @{} }
        if ($Present -contains 'Policy') { $null = New-ItemProperty -Path $policyPath -Name 'TestSetting' -Value 'Policy' }
        if ($Present -contains 'CommandLine') { $params.CommandLine = @{ TestSetting = 'CommandLine' } }
        if ($Present -contains 'Mod') { $params.ModSettings = @{ TestSetting = 'Mod' } }
        if ($Present -contains 'Local') { $null = New-ItemProperty -Path $localPath -Name 'TestSetting' -Value 'Local' }
        if ($Present -contains 'Config') { $params.Config = @{ TestSetting = 'Config' } }
        if ($Present -contains 'Default') { $params.Default = 'Default' }

        $result = Get-WingetFWSetting @params

        $result.Source | Should -Be $Expected
        if ($Expected -eq 'None') { $result.Value | Should -BeNullOrEmpty }
        else { $result.Value | Should -Be $Expected }
    }

    It 'Returns a DWORD policy value as a number' {
        $null = New-ItemProperty -Path $policyPath -Name 'DefaultSilent' -Value 0 -PropertyType DWord
        $result = Get-WingetFWSetting -Name 'DefaultSilent' -PolicyPath $policyPath -LocalPath $localPath -Default 1
        $result.Source | Should -Be 'Policy'
        $result.Value | Should -Be 0
        $result.Value | Should -BeOfType [int]
    }

    It 'Keeps a REG_MULTI_SZ value with one entry as an array' {
        $null = New-ItemProperty -Path $localPath -Name 'ScriptRoot' -Value @('\\fs01\WingetFW\Mods') -PropertyType MultiString
        $result = Get-WingetFWSetting -Name 'ScriptRoot' -PolicyPath $policyPath -LocalPath $localPath
        $result.Source | Should -Be 'Local'
        , $result.Value | Should -BeOfType [array]
        $result.Value.Count | Should -Be 1
    }

    It 'Counts an explicit switch set to $false on the command line' {
        function Test-CommandLine { param ([switch]$silent) Get-WingetFWSetting -Name 'silent' -CommandLine $PSBoundParameters -Config @{ silent = $true } -PolicyPath $policyPath -LocalPath $localPath }
        $result = Test-CommandLine -silent:$false
        $result.Source | Should -Be 'CommandLine'
        [bool]$result.Value | Should -BeFalse
    }

    It 'Does not count a $null value as set' {
        $result = Get-WingetFWSetting -Name 'Proxy' -CommandLine @{ Proxy = $null } -Config @{ Proxy = 'http://proxy.contoso.com:8080' } -PolicyPath $policyPath -LocalPath $localPath
        $result.Source | Should -Be 'Config'
    }

    It 'Masks SAS signatures in the log' {
        $null = New-ItemProperty -Path $policyPath -Name 'ScriptRoot' -Value 'https://contoso.blob.core.windows.net/mods?sp=r&sig=SECRETVALUE'
        $null = Get-WingetFWSetting -Name 'ScriptRoot' -PolicyPath $policyPath -LocalPath $localPath
        Should -Invoke -ModuleName 'WingetFW.Core' -CommandName 'Write-WingetFWLog' -Times 1 -Exactly -ParameterFilter {
            $Message -match 'sig=\*\*\*' -and $Message -notmatch 'SECRETVALUE'
        }
    }

    It 'Reads an ADMX list key (values 1, 2, 3 ...) as an ordered array' {
        $listKey = New-Item -Path (Join-Path -Path $policyPath -ChildPath 'AllowedSources') -Force
        foreach ($entry in @(@('2', 'msstore'), @('10', 'contoso'), @('1', 'winget')))
        {
            $null = New-ItemProperty -Path $listKey.PSPath -Name $entry[0] -Value $entry[1]
        }
        $result = Get-WingetFWSetting -Name 'AllowedSources' -PolicyPath $policyPath -LocalPath $localPath
        $result.Source | Should -Be 'Policy'
        $result.Value | Should -Be @('winget', 'msstore', 'contoso')
    }

    It 'Reads an ADMX list key with named values as a name/value table' {
        $listKey = New-Item -Path (Join-Path -Path $localPath -ChildPath 'Sources') -Force
        $null = New-ItemProperty -Path $listKey.PSPath -Name 'ContosoRest' -Value 'https://winget.contoso.com/api'
        $result = Get-WingetFWSetting -Name 'Sources' -PolicyPath $policyPath -LocalPath $localPath
        $result.Source | Should -Be 'Local'
        $result.Value | Should -BeOfType [System.Collections.IDictionary]
        $result.Value['ContosoRest'] | Should -Be 'https://winget.contoso.com/api'
        Should -Invoke -ModuleName 'WingetFW.Core' -CommandName 'Write-WingetFWLog' -Times 1 -Exactly -ParameterFilter { $Message -match 'ContosoRest=https://winget\.contoso\.com/api' }
    }

    It 'Ignores an empty list key' {
        $null = New-Item -Path (Join-Path -Path $policyPath -ChildPath 'AllowedSources') -Force
        (Get-WingetFWSetting -Name 'AllowedSources' -PolicyPath $policyPath -LocalPath $localPath -Config @{ AllowedSources = @('winget') }).Source | Should -Be 'Config'
    }

    It '-AsBoolean turns <Raw> into <Expected>' -ForEach @(
        @{ Raw = 1; Expected = $true }
        @{ Raw = 0; Expected = $false }
        @{ Raw = '1'; Expected = $true }
        @{ Raw = '0'; Expected = $false }
        @{ Raw = 'true'; Expected = $true }
        @{ Raw = 'False'; Expected = $false }
        @{ Raw = $true; Expected = $true }
        @{ Raw = $false; Expected = $false }
    ) {
        $result = Get-WingetFWSetting -Name 'DefaultSilent' -Config @{ DefaultSilent = $Raw } -PolicyPath $policyPath -LocalPath $localPath -AsBoolean
        $result.Value | Should -BeOfType [bool]
        $result.Value | Should -Be $Expected
    }

    It '-AsBoolean converts a DWORD from the policy key' {
        $null = New-ItemProperty -Path $policyPath -Name 'TlsCheck' -Value 0 -PropertyType DWord
        (Get-WingetFWSetting -Name 'TlsCheck' -PolicyPath $policyPath -LocalPath $localPath -Default $true -AsBoolean).Value | Should -BeFalse
    }
}

Describe 'Write-WingetFWLog' {
    It 'Writes a CMTrace line with message, component and severity' {
        $logFile = Join-Path -Path $TestDrive -ChildPath 'Logs\test.log'
        Write-WingetFWLog -Message 'Hello WingetFW' -Severity 2 -Source 'Pester' -LogFile $logFile
        $line = Get-Content -LiteralPath $logFile -Encoding UTF8 | Select-Object -Last 1
        $line | Should -Match '^<!\[LOG\[Hello WingetFW\]LOG\]!><time="\d{2}:\d{2}:\d{2}\.\d{3}[+-]\d+" date="\d{1,2}-\d{1,2}-\d{4}" component="Pester" context=".+" type="2" thread="\d+" file="">$'
    }

    It 'Uses the PSAppDeployToolkit log when a PSADT session is open' {
        function global:Test-ADTSessionActive { $false }
        function global:Write-ADTLogEntry { param ($Message, $Severity, $Source) }
        try
        {
            Mock -ModuleName 'WingetFW.Core' -CommandName 'Test-ADTSessionActive' -MockWith { $true }
            Mock -ModuleName 'WingetFW.Core' -CommandName 'Write-ADTLogEntry' -MockWith { }
            Write-WingetFWLog -Message 'To PSADT' -Source 'Pester'
            Should -Invoke -ModuleName 'WingetFW.Core' -CommandName 'Write-ADTLogEntry' -Times 1 -Exactly -ParameterFilter { $Message -eq 'To PSADT' -and $Source -eq 'Pester' }
        }
        finally
        {
            Remove-Item -Path 'Function:\Test-ADTSessionActive', 'Function:\Write-ADTLogEntry' -ErrorAction SilentlyContinue
        }
    }

    It 'Does not throw when the log file cannot be written' {
        $badFile = Join-Path -Path $TestDrive -ChildPath 'bad|name.log'
        { Write-WingetFWLog -Message 'x' -LogFile $badFile -WarningAction SilentlyContinue } | Should -Not -Throw
    }
}

Describe 'Event log' {
    BeforeAll {
        # Only the first 8 characters of a custom log name must be unique, so the test log does not start with "WingetFW".
        $testLog = 'WFWPester'
        $testSource = 'WFWPesterSource'
    }

    It 'Register-WingetFWEventLog throws without administrator rights' {
        Mock -ModuleName 'WingetFW.Core' -CommandName 'Test-WingetFWElevated' -MockWith { $false }
        { Register-WingetFWEventLog -LogName $testLog -Source $testSource } | Should -Throw '*administrator*'
    }

    It 'Write-WingetFWEvent logs a warning instead of failing when the event log is missing and it is not elevated' {
        Mock -ModuleName 'WingetFW.Core' -CommandName 'Test-WingetFWElevated' -MockWith { $false }
        Mock -ModuleName 'WingetFW.Core' -CommandName 'Write-WingetFWLog' -MockWith { }
        { Write-WingetFWEvent -Message 'x' -LogName 'WFWNoSuchLog' -Source 'WFWNoSuchSource' } | Should -Not -Throw
        Should -Invoke -ModuleName 'WingetFW.Core' -CommandName 'Write-WingetFWLog' -Times 1 -Exactly -ParameterFilter { $Severity -eq 2 }
    }

    Context '[admin] real event log' -Skip:(-not $isAdmin) {
        AfterAll {
            if ([Diagnostics.EventLog]::Exists($testLog)) { [Diagnostics.EventLog]::Delete($testLog) }
        }

        It 'Creates the event log and writes an entry' {
            Mock -ModuleName 'WingetFW.Core' -CommandName 'Write-WingetFWLog' -MockWith { }
            Write-WingetFWEvent -Message 'Pester event' -EntryType 'Warning' -EventId 1234 -LogName $testLog -Source $testSource

            [Diagnostics.EventLog]::Exists($testLog) | Should -BeTrue
            $eventLog = New-Object -TypeName Diagnostics.EventLog -ArgumentList $testLog
            try
            {
                $entry = $eventLog.Entries | Select-Object -Last 1
                $entry.Message | Should -Be 'Pester event'
                $entry.EntryType | Should -Be 'Warning'
                $entry.InstanceId | Should -Be 1234
            }
            finally
            {
                $eventLog.Dispose()
            }
            Should -Invoke -ModuleName 'WingetFW.Core' -CommandName 'Write-WingetFWLog' -Times 0 -Exactly -ParameterFilter { $Severity -eq 2 }
        }

        It 'Register-WingetFWEventLog is safe to run again' {
            { Register-WingetFWEventLog -LogName $testLog -Source $testSource } | Should -Not -Throw
        }
    }
}

Describe 'State files' {
    BeforeAll {
        Mock -ModuleName 'WingetFW.Core' -CommandName 'Write-WingetFWLog' -MockWith { }
    }

    Context 'User scope' {
        BeforeAll {
            $root = Join-Path -Path $TestDrive -ChildPath 'User'
        }

        It 'Returns $null when there is no state file' {
            Get-WingetFWState -Id 'Contoso.None' -Scope 'User' -Root $root | Should -BeNullOrEmpty
        }

        It 'Writes and reads a state file' {
            Set-WingetFWState -Id '7zip.7zip' -Scope 'User' -Root $root -Source 'winget' -ModFile '\\fs01\WingetFW\Mods\winget\7zip.7zip.ps1' -LastAction 'Install' -LastResult 0

            $state = Get-WingetFWState -Id '7zip.7zip' -Scope 'User' -Root $root
            $state.SchemaVersion | Should -Be 1
            $state.Id | Should -Be '7zip.7zip'
            $state.Scope | Should -Be 'User'
            $state.UserSid | Should -Be ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
            $state.Managed | Should -BeTrue
            $state.Source | Should -Be 'winget'
            $state.ModFile | Should -Be '\\fs01\WingetFW\Mods\winget\7zip.7zip.ps1'
            $state.Pinned | Should -BeFalse
            $state.LastAction | Should -Be 'Install'
            $state.LastResult | Should -Be 0
            [datetime]::Parse($state.LastTime, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).Kind | Should -Be 'Utc'
        }

        It 'Keeps values that are not given and leaves no temp file' {
            Set-WingetFWState -Id '7zip.7zip' -Scope 'User' -Root $root -LastAction 'Upgrade' -LastResult -1978335212

            $state = Get-WingetFWState -Id '7zip.7zip' -Scope 'User' -Root $root
            $state.Source | Should -Be 'winget'
            $state.LastAction | Should -Be 'Upgrade'
            $state.LastResult | Should -Be -1978335212
            Get-ChildItem -LiteralPath (Join-Path -Path $root -ChildPath 'State') -Filter '*.tmp' | Should -BeNullOrEmpty
        }

        It 'Does not touch LastTime when only other values change' {
            $before = (Get-WingetFWState -Id '7zip.7zip' -Scope 'User' -Root $root).LastTime
            Set-WingetFWState -Id '7zip.7zip' -Scope 'User' -Root $root -Pinned $true
            $state = Get-WingetFWState -Id '7zip.7zip' -Scope 'User' -Root $root
            $state.Pinned | Should -BeTrue
            $state.LastTime | Should -Be $before
        }

        It 'Writes nothing with -WhatIf' {
            Set-WingetFWState -Id 'Contoso.WhatIf' -Scope 'User' -Root $root -LastAction 'Install' -LastResult 0 -WhatIf
            Get-WingetFWState -Id 'Contoso.WhatIf' -Scope 'User' -Root $root | Should -BeNullOrEmpty
        }

        It 'Returns $null and logs a warning for a damaged state file' {
            $file = Join-Path -Path $root -ChildPath 'State\Contoso.Broken.json'
            Set-Content -LiteralPath $file -Value '{ not json' -Encoding UTF8
            Get-WingetFWState -Id 'Contoso.Broken' -Scope 'User' -Root $root | Should -BeNullOrEmpty
            Should -Invoke -ModuleName 'WingetFW.Core' -CommandName 'Write-WingetFWLog' -ParameterFilter { $Severity -eq 2 -and $Source -eq 'Get-WingetFWState' }
        }

        It 'Rejects the ID <Id>' -ForEach @(
            @{ Id = '..' }
            @{ Id = '..\..\evil' }
            @{ Id = 'a/b' }
            @{ Id = 'C:evil' }
        ) {
            { Set-WingetFWState -Id $Id -Scope 'User' -Root $root -LastResult 0 } | Should -Throw
            { Get-WingetFWState -Id $Id -Scope 'User' -Root $root } | Should -Throw
        }
    }

    Context 'Machine scope' {
        It 'Throws without administrator rights' {
            Mock -ModuleName 'WingetFW.Core' -CommandName 'Test-WingetFWElevated' -MockWith { $false }
            { Set-WingetFWState -Id '7zip.7zip' -Scope 'Machine' -Root (Join-Path -Path $TestDrive -ChildPath 'NoAdmin') -LastResult 0 } | Should -Throw '*administrator*'
        }

        It '[admin] secures the folders: owner Administrators, SYSTEM and Administrators full control, Users read' -Skip:(-not $isAdmin) {
            $root = Join-Path -Path $TestDrive -ChildPath 'Machine'
            $null = New-Item -Path $root -ItemType Directory -Force
            Set-WingetFWState -Id '7zip.7zip' -Scope 'Machine' -Root $root -LastAction 'Install' -LastResult 0

            (Get-WingetFWState -Id '7zip.7zip' -Scope 'Machine' -Root $root).UserSid | Should -BeNullOrEmpty
            foreach ($path in @($root, (Join-Path -Path $root -ChildPath 'State')))
            {
                $acl = Get-Acl -LiteralPath $path
                $acl.AreAccessRulesProtected | Should -BeTrue
                $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value | Should -Be 'S-1-5-32-544'
                $rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | ForEach-Object {
                    '{0}:{1}' -f $_.IdentityReference.Value, $_.FileSystemRights
                }) | Sort-Object
                $rules | Should -Be @('S-1-5-18:FullControl', 'S-1-5-32-544:FullControl', 'S-1-5-32-545:ReadAndExecute, Synchronize')
            }
        }
    }
}
