<#
.SYNOPSIS
    Pester tests for Policies\WingetFW.admx and Policies\en-US\WingetFW.adml.

.DESCRIPTION
    Checks that both files are valid XML, that every string and presentation the ADMX uses is in the ADML,
    that every presentation control belongs to an element of its policy, and that all policies write to
    Software\Policies\WingetFW with the setting names WingetFW reads.

.NOTES
    Maintained by: KSKITDK
    Version      : 1.0.0

    Release notes
    1.0.0  - First version.

.LINK
    https://github.com/ksk-itdk/PSADT-WingetFW
#>

BeforeAll {
    $policyDir = Join-Path -Path $PSScriptRoot -ChildPath '..\..\Policies'
    [xml]$admx = Get-Content -LiteralPath (Join-Path -Path $policyDir -ChildPath 'WingetFW.admx') -Raw -Encoding UTF8
    [xml]$adml = Get-Content -LiteralPath (Join-Path -Path $policyDir -ChildPath 'en-US\WingetFW.adml') -Raw -Encoding UTF8
    $admxText = $admx.OuterXml
    $stringIds = @($adml.policyDefinitionResources.resources.stringTable.string | ForEach-Object { $_.id })
    $presentations = @($adml.policyDefinitionResources.resources.presentationTable.presentation)
    $policies = @($admx.policyDefinitions.policies.policy)
}

Describe 'WingetFW ADMX/ADML' {
    It 'Every $(string.x) in the ADMX is in the ADML' {
        $missing = @([regex]::Matches($admxText, '\$\(string\.([^)]+)\)') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -notin $stringIds })
        $missing | Should -BeNullOrEmpty
    }

    It 'Every $(presentation.x) in the ADMX is in the ADML' {
        $missing = @([regex]::Matches($admxText, '\$\(presentation\.([^)]+)\)') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -notin $presentations.id })
        $missing | Should -BeNullOrEmpty
    }

    It 'Every presentation control points to an element of its policy' {
        foreach ($policy in @($policies | Where-Object { $_.presentation }))
        {
            $presentationId = [regex]::Match($policy.presentation, '\$\(presentation\.([^)]+)\)').Groups[1].Value
            $elementIds = @($policy.elements.ChildNodes | Where-Object { $_.NodeType -eq 'Element' } | ForEach-Object { $_.id })
            $refIds = @(($presentations | Where-Object { $_.id -eq $presentationId }).ChildNodes | Where-Object { $_.NodeType -eq 'Element' } | ForEach-Object { $_.refId })
            $refIds | Sort-Object | Should -Be ($elementIds | Sort-Object) -Because "policy $($policy.name)"
        }
    }

    It 'All policies are machine policies under Software\Policies\WingetFW' {
        foreach ($policy in $policies)
        {
            $policy.class | Should -Be 'Machine'
            $policy.key | Should -BeLike 'Software\Policies\WingetFW*'
        }
    }

    It 'Writes the setting names WingetFW reads' {
        $names = @(foreach ($policy in $policies)
            {
                if ($policy.valueName) { $policy.valueName }
                foreach ($element in @($policy.elements.ChildNodes | Where-Object { $_.NodeType -eq 'Element' }))
                {
                    if ($element.valueName) { $element.valueName }
                    elseif ($element.key) { Split-Path -Path $element.key -Leaf }
                }
            })
        $names | Sort-Object | Should -Be (@('AllowedScriptSources', 'AllowedSources', 'DefaultSilent', 'DefaultSource', 'Proxy', 'ProxyBypass', 'RequireSignedScripts', 'ScriptRoot', 'ScriptSyncMode', 'Sources', 'TlsCheck', 'TrustedSigners', 'UseCachedScriptsWhenOffline', 'VCRedistCheck') | Sort-Object)
    }
}
