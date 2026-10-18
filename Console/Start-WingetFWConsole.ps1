#Requires -Version 7.4

<#
.SYNOPSIS
    Starts the WingetFW Console: search winget packages and build the WingetFW install and uninstall
    commands and the detection script for an Intune app.

.DESCRIPTION
    One window with tabs. Tab "Search and build" (phase CON-1):
    1. Search a winget source by name, ID, moniker or tag.
    2. Select a package and version to see the manifest details and installers
       (source winget: from GitHub winget-pkgs; other sources: winget show).
       Selecting an installer fills in its scope, architecture and installer type.
    3. The install and uninstall commands for Invoke-AppDeployToolkit.exe are built while you type and
       checked with the WingetFW option rules (the cases where WingetFW stops with 60001 or 69001).
    4. Copy or save the detection script (winget list or uninstall registry key).

    Nothing is changed in Intune or on this device. Publishing comes in a later version.

    Needs PowerShell 7.4 or later and the modules Microsoft.WinGet.Client (search) and powershell-yaml
    (manifest details). Runs from the repository folder: it reads Toolkit\WinGetFW<version>,
    Toolkit\Detection and Tools\WingetFW-ParameterMap.psd1.

.EXAMPLE
    pwsh -File .\Console\Start-WingetFWConsole.ps1

.NOTES
    Maintained by: KSKITDK
    Version      : 0.1.0

    Release notes
    0.1.0  - First version (phase CON-1): search, manifest details, install and uninstall commands,
             detection script.

.LINK
    https://github.com/ksk-itdk/PSADT-WingetFW
#>
[CmdletBinding()]
param ()

$ErrorActionPreference = 'Stop'
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw 'The WingetFW Console needs an STA thread. Start it with: pwsh -STA -File Start-WingetFWConsole.ps1' }
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath 'WingetFW.Console\WingetFW.Console.psd1'
Import-Module -Name $moduleManifest -Force

$xamlText = [System.IO.File]::ReadAllText((Join-Path -Path $PSScriptRoot -ChildPath 'MainWindow.xaml'))
$window = [System.Windows.Markup.XamlReader]::Parse($xamlText)
$ui = @{}
foreach ($match in [regex]::Matches($xamlText, 'x:Name="(\w+)"')) { $ui[$match.Groups[1].Value] = $window.FindName($match.Groups[1].Value) }

$package = Get-WingetFWPackageInfo
$window.Title = "WingetFW Console $((Import-PowerShellDataFile -LiteralPath $moduleManifest).ModuleVersion) - WingetFW $($package.Version)"
$notSet = '(not set)'
$templates = @{
    Winget   = (New-WingetFWDetectionScript -Type Winget -Id 'x').Template
    Registry = (New-WingetFWDetectionScript -Type Registry -AppName 'x').Template
}
$script:filling = $false

#region Helpers
function Set-Status([string]$Text)
{
    $ui.StatusText.Text = $Text
    # Let WPF draw the status before a slow call
    $window.Dispatcher.Invoke([action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
}

function Invoke-UiAction([string]$Status, [scriptblock]$Action)
{
    $window.Cursor = [System.Windows.Input.Cursors]::Wait
    try
    {
        if ($Status) { Set-Status $Status }
        & $Action
    }
    catch
    {
        Set-Status "Error: $($_.Exception.Message)"
        $null = [System.Windows.MessageBox]::Show($window, $_.Exception.Message, 'WingetFW Console', 'OK', 'Error')
    }
    finally { $window.Cursor = $null }
}

function Select-ComboValue($Combo, [string]$Value)
{
    $item = $Combo.ItemsSource | Where-Object { $_ -ieq $Value } | Select-Object -First 1
    $Combo.SelectedItem = if ($null -ne $item) { $item } else { $notSet }
}

function Get-ComboValue($Combo)
{
    if ($Combo.SelectedItem -and $Combo.SelectedItem -ne $notSet) { [string]$Combo.SelectedItem }
}

function Format-ManifestDetails($Manifest)
{
    if ($Manifest.ShowText) { return $Manifest.ShowText }
    $lines = @(
        "Name        : $($Manifest.Name)"
        "Publisher   : $($Manifest.Publisher)"
        "ID          : $($Manifest.Id)"
        "Version     : $($Manifest.Version)"
        "Moniker     : $($Manifest.Moniker)"
        "License     : $($Manifest.License)"
        "Homepage    : $($Manifest.PackageUrl)"
        "Tags        : $($Manifest.Tags -join ', ')"
        "Dependencies: $(if ($Manifest.Dependencies) { $Manifest.Dependencies -join ', ' } else { 'none' })"
        "Installers  : $($Manifest.Installers.Count)"
        ''
        $Manifest.ShortDescription
    )
    $lines -join "`r`n"
}

function Get-BuildParameters
{
    $parameters = [ordered]@{ DeploymentType = 'Install' }
    $messages = [System.Collections.Generic.List[string]]::new()
    if ($ui.ActionBox.SelectedItem -eq 'upgrade') { $parameters['Action'] = 'upgrade' }
    if ($ui.ModeBox.SelectedItem -eq 'User') { $parameters['Mode'] = 'User' }
    $parameters['id'] = $ui.IdText.Text
    $parameters['exact'] = [bool]$ui.ExactCheck.IsChecked
    if ($ui.SourceCheck.IsChecked) { $parameters['source'] = $ui.SourceText.Text }
    $parameters['version'] = $ui.PinVersionText.Text
    $parameters['scope'] = Get-ComboValue $ui.ScopeBox
    $parameters['architecture'] = Get-ComboValue $ui.ArchitectureBox
    $parameters['installertype'] = Get-ComboValue $ui.InstallerTypeBox
    $installMode = Get-ComboValue $ui.InstallModeBox
    if ($installMode) { $parameters[$installMode] = $true }
    $parameters['custom'] = $ui.CustomText.Text
    $parameters['override'] = $ui.OverrideText.Text
    $parameters['log'] = $ui.LogText.Text

    $other = ConvertFrom-WingetFWCommandLine -CommandLine $ui.OtherText.Text
    foreach ($text in $other.Errors) { $messages.Add("Error in Other options: $text") }
    foreach ($name in $other.Parameters.Keys)
    {
        if ($parameters.Contains($name) -and $parameters[$name]) { $messages.Add("Warning: -$name is set above and in Other options; Other options is used") }
        $parameters[$name] = $other.Parameters[$name]
    }
    [pscustomobject]@{ Parameters = $parameters; Messages = $messages }
}

function Update-Commands
{
    if ($script:filling) { return }
    $build = Get-BuildParameters
    $install = New-WingetFWCommandLine -Parameters $build.Parameters
    $uninstall = New-WingetFWCommandLine -Parameters $install.Parameters -Uninstall
    $ui.InstallCommandText.Text = $install.CommandLine
    $ui.UninstallCommandText.Text = $uninstall.CommandLine

    $messages = [System.Collections.Generic.List[string]]::new()
    foreach ($text in $build.Messages) { $messages.Add($text) }
    foreach ($text in $install.Errors) { $messages.Add("Error: $text") }
    foreach ($text in $install.Warnings) { $messages.Add("Warning: $text") }
    foreach ($text in $uninstall.Errors) { if ($text -notin $install.Errors) { $messages.Add("Uninstall error: $text") } }
    if ($uninstall.Dropped.Count) { $messages.Add("Uninstall leaves out: $($uninstall.Dropped -join ' ')") }
    if ($ui.DetectRegistryRadio.IsChecked -and ($install.Parameters['Mode'] -eq 'User' -or $install.Parameters['scope'] -eq 'User'))
    {
        $messages.Add('Warning: the registry detection script reads HKLM only; a user-scope app is registered in HKCU. Use winget list.')
    }
    if (-not @($messages | Where-Object { $_ -match '^(Error|Uninstall error)' }).Count) { $messages.Insert(0, 'OK: the commands follow the WingetFW option rules') }
    $ui.MessagesList.ItemsSource = $messages.ToArray()

    $ui.DetectTemplateText.Text = "Template: $(if ($ui.DetectRegistryRadio.IsChecked) { $templates.Registry } else { $templates.Winget })"
    $ui.DetectNameText.IsEnabled = [bool]$ui.DetectRegistryRadio.IsChecked
    $ui.DetectVersionText.IsEnabled = [bool]$ui.DetectRegistryRadio.IsChecked
}

function Get-DetectionScript([string]$Path)
{
    $detectParams = @{}
    if ($Path) { $detectParams.Path = $Path }
    if ($ui.DetectRegistryRadio.IsChecked)
    {
        New-WingetFWDetectionScript -Type Registry -AppName $ui.DetectNameText.Text.Trim() -AppVersion $ui.DetectVersionText.Text.Trim() @detectParams
    }
    else
    {
        New-WingetFWDetectionScript -Type Winget -Id $ui.IdText.Text.Trim() @detectParams
    }
}
#endregion

#region Start values
$sources = @('winget', 'msstore')
try
{
    if (Get-Module -Name 'Microsoft.WinGet.Client' -ListAvailable)
    {
        Import-Module -Name 'Microsoft.WinGet.Client'
        $sources = @(Get-WinGetSource | ForEach-Object { $_.Name })
    }
}
catch { Write-Verbose "winget sources could not be read: $($_.Exception.Message)" }
$ui.SearchSourceBox.ItemsSource = $sources
$ui.SearchSourceBox.SelectedItem = if ('winget' -in $sources) { 'winget' } else { $sources[0] }

$ui.ActionBox.ItemsSource = @('Install', 'upgrade')
$ui.ActionBox.SelectedIndex = 0
$ui.ModeBox.ItemsSource = @($package.Parameters['Mode'].Values)
$ui.ModeBox.SelectedItem = 'Admin'
$ui.ScopeBox.ItemsSource = @($notSet) + $package.Parameters['scope'].Values
$ui.ArchitectureBox.ItemsSource = @($notSet) + $package.Parameters['architecture'].Values
$ui.InstallerTypeBox.ItemsSource = @($notSet) + $package.Parameters['installertype'].Values
$ui.InstallModeBox.ItemsSource = @($notSet, 'silent', 'interactive')
foreach ($combo in $ui.ScopeBox, $ui.ArchitectureBox, $ui.InstallerTypeBox, $ui.InstallModeBox) { $combo.SelectedIndex = 0 }
#endregion

#region Events
$ui.SearchButton.Add_Click({
        $query = $ui.SearchText.Text.Trim()
        if (-not $query) { Set-Status 'Type a name, ID, moniker or tag to search for'; return }
        Invoke-UiAction "Searching $($ui.SearchSourceBox.SelectedItem) for '$query'..." {
            $found = @(Find-WingetFWPackage -Query $query -Source $ui.SearchSourceBox.SelectedItem)
            $ui.ResultsGrid.ItemsSource = $found
            Set-Status "$($found.Count) package(s) found"
        }
    })

$ui.ResultsGrid.Add_SelectionChanged({
        $selected = $ui.ResultsGrid.SelectedItem
        if (-not $selected) { return }
        $script:filling = $true
        $ui.IdText.Text = $selected.Id
        $ui.SourceText.Text = $selected.Source
        $ui.DetailsText.Text = ''
        $ui.InstallersGrid.ItemsSource = $null
        $script:filling = $false
        $ui.VersionBox.ItemsSource = @(if ($selected.AvailableVersions.Count) { $selected.AvailableVersions } else { $selected.Version })
        $ui.VersionBox.SelectedIndex = 0
        Update-Commands
    })

$ui.VersionBox.Add_SelectionChanged({
        $selected = $ui.ResultsGrid.SelectedItem
        $version = $ui.VersionBox.SelectedItem
        if (-not $selected -or -not $version) { return }
        Invoke-UiAction "Reading the manifest of $($selected.Id) $version..." {
            $manifest = Get-WingetFWManifest -Id $selected.Id -Version $version -Source $selected.Source
            $ui.DetailsText.Text = Format-ManifestDetails $manifest
            $ui.InstallersGrid.ItemsSource = @($manifest.Installers)
            $ui.DetectNameText.Text = "$(if ($manifest.Name) { $manifest.Name } else { $selected.Name })*"
            Set-Status "$($selected.Id) $version - $($manifest.Installers.Count) installer(s)"
        }
    })

$ui.InstallersGrid.Add_SelectionChanged({
        $installer = $ui.InstallersGrid.SelectedItem
        if (-not $installer) { return }
        $script:filling = $true
        Select-ComboValue $ui.ScopeBox $installer.Scope
        Select-ComboValue $ui.ArchitectureBox $installer.Architecture
        Select-ComboValue $ui.InstallerTypeBox $installer.InstallerType
        # A user-scope installer needs WingetFW user mode (Intune install behavior User)
        if ($installer.Scope -eq 'user') { $ui.ModeBox.SelectedItem = 'User' }
        elseif ($installer.Scope -eq 'machine') { $ui.ModeBox.SelectedItem = 'Admin' }
        $script:filling = $false
        Update-Commands
    })

foreach ($name in 'IdText', 'SourceText', 'PinVersionText', 'CustomText', 'OverrideText', 'LogText', 'OtherText') { $ui[$name].Add_TextChanged({ Update-Commands }) }
foreach ($name in 'ActionBox', 'ModeBox', 'ScopeBox', 'ArchitectureBox', 'InstallerTypeBox', 'InstallModeBox') { $ui[$name].Add_SelectionChanged({ Update-Commands }) }
foreach ($name in 'ExactCheck', 'SourceCheck', 'DetectWingetRadio', 'DetectRegistryRadio')
{
    $ui[$name].Add_Checked({ Update-Commands })
    $ui[$name].Add_Unchecked({ Update-Commands })
}

$ui.CopyInstallButton.Add_Click({ [System.Windows.Clipboard]::SetText($ui.InstallCommandText.Text); Set-Status 'Install command copied' })
$ui.CopyUninstallButton.Add_Click({ [System.Windows.Clipboard]::SetText($ui.UninstallCommandText.Text); Set-Status 'Uninstall command copied' })
$ui.CopyDetectionButton.Add_Click({
        Invoke-UiAction '' {
            $detection = Get-DetectionScript
            [System.Windows.Clipboard]::SetText($detection.Text)
            Set-Status "Detection script copied ($($detection.Template))"
        }
    })
$ui.SaveDetectionButton.Add_Click({
        Invoke-UiAction '' {
            $dialog = New-Object -TypeName Microsoft.Win32.SaveFileDialog
            $dialog.Filter = 'PowerShell script (*.ps1)|*.ps1'
            $dialog.FileName = "$(if ($ui.IdText.Text.Trim()) { $ui.IdText.Text.Trim() } else { 'app' })-detection.ps1"
            if (-not $dialog.ShowDialog($window)) { return }
            $detection = Get-DetectionScript -Path $dialog.FileName
            Set-Status "Detection script saved to $($dialog.FileName) ($($detection.Template))"
        }
    })
#endregion

Update-Commands
$null = $window.ShowDialog()
