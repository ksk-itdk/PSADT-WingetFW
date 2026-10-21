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

    Tab "Publish to Intune" (phase CON-2): sign in (delegated), select or build the .intunewin, and create
    the Win32 app with the commands and detection script of the first tab, requirements, return codes and
    optional group assignments. Nothing is changed in Intune before you confirm.

    Needs PowerShell 7.4 or later and the modules Microsoft.WinGet.Client (search), powershell-yaml
    (manifest details) and Microsoft.Graph.Authentication (Intune). Runs from the repository folder: it reads Toolkit\WinGetFW<version>,
    Toolkit\Detection and Tools\WingetFW-ParameterMap.psd1.

.EXAMPLE
    pwsh -File .\Console\Start-WingetFWConsole.ps1

.NOTES
    Maintained by: KSKITDK
    Version      : 0.2.0

    Release notes
    0.2.0  - Tab "Publish to Intune" (phase CON-2): sign-in, .intunewin (browse or build), app details,
             requirements, group assignments, create the Win32 app.
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
$script:assignments = [System.Collections.ObjectModel.ObservableCollection[object]]::new()

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

    $ui.PublishInstallText.Text = $install.CommandLine
    $ui.PublishUninstallText.Text = $uninstall.CommandLine
    $ui.InstallBehaviorText.Text = if ($install.Parameters['Mode'] -eq 'User') { 'User (-Mode User)' } else { 'System (-Mode Admin)' }
    $ui.PublishDetectionText.Text = if ($ui.DetectRegistryRadio.IsChecked) { "$($templates.Registry): $($ui.DetectNameText.Text) >= $($ui.DetectVersionText.Text)" } else { "$($templates.Winget): $($ui.IdText.Text)" }
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

$ui.RequirementArchBox.ItemsSource = @('x64', 'x64,arm64', 'x86,x64', 'x86,x64,arm64', 'arm64')
$ui.RequirementArchBox.SelectedIndex = 0
$ui.MinWindowsBox.ItemsSource = @('1809', '1903', '1909', '2004', '2H20', '21H1', 'Windows10_21H2', 'Windows10_22H2', 'Windows11_21H2', 'Windows11_22H2', 'Windows11_23H2')
$ui.MinWindowsBox.SelectedIndex = 0
$ui.IntentBox.ItemsSource = @('required', 'available', 'uninstall')
$ui.IntentBox.SelectedIndex = 0
$ui.AssignmentsGrid.ItemsSource = $script:assignments
$defaultIntuneWin = Join-Path -Path $env:LOCALAPPDATA -ChildPath "WingetFW\Console\IntuneWin\$(Split-Path -Path $package.Path -Leaf)\Invoke-AppDeployToolkit.intunewin"
if (Test-Path -LiteralPath $defaultIntuneWin) { $ui.IntuneWinText.Text = $defaultIntuneWin }
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
            $ui.AppNameText.Text = if ($manifest.Name) { $manifest.Name } else { $selected.Name }
            $ui.AppPublisherText.Text = $manifest.Publisher
            $ui.AppDescriptionText.Text = $manifest.ShortDescription
            $ui.AppUrlText.Text = $manifest.PackageUrl
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

foreach ($name in 'IdText', 'SourceText', 'PinVersionText', 'CustomText', 'OverrideText', 'LogText', 'OtherText', 'DetectNameText', 'DetectVersionText') { $ui[$name].Add_TextChanged({ Update-Commands }) }
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

$ui.SignInButton.Add_Click({
        Invoke-UiAction 'Signing in (see the browser window)...' {
            $context = Connect-WingetFWIntune -TenantId $ui.TenantText.Text.Trim()
            $ui.SignedInText.Text = "$($context.Account) - tenant $($context.TenantId)"
            Set-Status "Signed in as $($context.Account)"
        }
    })

$ui.BrowseIntuneWinButton.Add_Click({
        $dialog = New-Object -TypeName Microsoft.Win32.OpenFileDialog
        $dialog.Filter = 'Intune package (*.intunewin)|*.intunewin'
        if ($dialog.ShowDialog($window)) { $ui.IntuneWinText.Text = $dialog.FileName }
    })

$ui.BuildIntuneWinButton.Add_Click({
        Invoke-UiAction "Building the .intunewin of WingetFW $($package.Version)..." {
            $ui.IntuneWinText.Text = New-WingetFWIntuneWin
            Set-Status "Built $($ui.IntuneWinText.Text)"
        }
    })

$ui.GroupSearchButton.Add_Click({
        $name = $ui.GroupSearchText.Text.Trim()
        if (-not $name) { Set-Status 'Type the start of a group name'; return }
        Invoke-UiAction "Finding groups '$name'..." {
            $groups = @(Find-WingetFWGroup -Name $name)
            $ui.GroupsList.ItemsSource = $groups
            Set-Status "$($groups.Count) group(s) found"
        }
    })

$ui.AddAssignmentButton.Add_Click({
        $group = $ui.GroupsList.SelectedItem
        if (-not $group) { Set-Status 'Select a group first'; return }
        if (@($script:assignments | Where-Object { $_.GroupId -eq $group.Id }).Count) { Set-Status "$($group.DisplayName) is already in the list"; return }
        $script:assignments.Add([pscustomobject]@{ Group = $group.DisplayName; GroupId = $group.Id; Intent = [string]$ui.IntentBox.SelectedItem })
    })

$ui.RemoveAssignmentButton.Add_Click({
        if ($ui.AssignmentsGrid.SelectedItem) { $null = $script:assignments.Remove($ui.AssignmentsGrid.SelectedItem) }
    })

$ui.PublishButton.Add_Click({
        $install = New-WingetFWCommandLine -Parameters (Get-BuildParameters).Parameters
        $uninstall = New-WingetFWCommandLine -Parameters $install.Parameters -Uninstall
        $problems = @($install.Errors) + @($uninstall.Errors | ForEach-Object { "Uninstall: $_" })
        if (-not $ui.AppNameText.Text.Trim()) { $problems += 'Name is empty' }
        if (-not $ui.AppPublisherText.Text.Trim()) { $problems += 'Publisher is empty' }
        if (-not (Test-Path -LiteralPath $ui.IntuneWinText.Text -PathType Leaf)) { $problems += 'Select or build the .intunewin' }
        if (-not (Get-Command -Name Get-MgContext -ErrorAction SilentlyContinue) -or -not (Get-MgContext)) { $problems += 'Sign in first' }
        if ($problems)
        {
            $null = [System.Windows.MessageBox]::Show($window, ($problems -join "`n"), 'WingetFW Console', 'OK', 'Warning')
            return
        }
        $question = "Create the app '$($ui.AppNameText.Text.Trim())' in tenant $((Get-MgContext).TenantId) with $($script:assignments.Count) assignment(s)?"
        if ([System.Windows.MessageBox]::Show($window, $question, 'WingetFW Console', 'YesNo', 'Question') -ne 'Yes') { return }

        Invoke-UiAction "Creating '$($ui.AppNameText.Text.Trim())' in Intune and uploading the package..." {
            $app = New-WingetFWIntuneApp -DisplayName $ui.AppNameText.Text.Trim() -Publisher $ui.AppPublisherText.Text.Trim() `
                -Description $ui.AppDescriptionText.Text.Trim() -InformationUrl $ui.AppUrlText.Text.Trim() `
                -InstallCommandLine $install.CommandLine -UninstallCommandLine $uninstall.CommandLine `
                -RunAsAccount $(if ($install.Parameters['Mode'] -eq 'User') { 'user' } else { 'system' }) `
                -DetectionScript (Get-DetectionScript).Text -IntuneWinFile $ui.IntuneWinText.Text `
                -AllowedArchitectures $ui.RequirementArchBox.SelectedItem -MinimumWindowsRelease $ui.MinWindowsBox.SelectedItem `
                -Assignments @($script:assignments)
            $ui.PublishResultText.Text = "Created '$($app.DisplayName)' (ID $($app.Id)) with $($app.Assignments) assignment(s)"
            Set-Status $ui.PublishResultText.Text
        }
    })
#endregion

Update-Commands
$null = $window.ShowDialog()
