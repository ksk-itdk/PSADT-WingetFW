# WingetFW parameter map used by Update-WingetFWIntuneApps.ps1.
# Describes how Deploy-Application.exe command lines from older WingetFW versions are converted to the current version (5.0.0, Invoke-AppDeployToolkit.exe),
# and the option rules the current version enforces (keep in sync with Start-WinGetPackageFM in PSAppDeployToolkit.Extensions.psm1).
@{
    # Setup file of the current WingetFW package, and the setup file of older versions it replaces
    ExeName = 'Invoke-AppDeployToolkit.exe'
    OldExeNames = @('Deploy-Application.exe')

    # Parameters of the current Invoke-AppDeployToolkit.ps1 and their type
    Parameters = @{
        DeploymentType = 'String'; DeployMode = 'String'; SuppressRebootPassThru = 'Switch'; TerminalServerMode = 'Switch'; DisableLogging = 'Switch'
        Mode = 'String'; Action = 'String'; OverrideAPPName = 'String'; ForceRepair = 'Switch'
        wingetmanifest = 'String'; id = 'String'; name = 'String'; moniker = 'String'; version = 'String'; source = 'String'
        scope = 'String'; architecture = 'String'; installertype = 'String'; exact = 'Switch'; interactive = 'Switch'; silent = 'Switch'
        locale = 'String'; log = 'String'; custom = 'String'; override = 'String'; location = 'String'
        ignoresecurityhash = 'Switch'; allowreboot = 'Switch'; skipdependencies = 'Switch'; ignorelocalarchivemalwarescan = 'Switch'
        dependencysource = 'String'; acceptpackageagreements = 'Switch'; noupgrade = 'Switch'; header = 'String'
        authenticationmode = 'String'; authenticationaccount = 'String'; acceptsourceagreements = 'Switch'; rename = 'String'
        uninstallprevious = 'Switch'; force = 'Switch'; enableverbose = 'Switch'; ignorewarnings = 'Switch'; disableinteractivity = 'Switch'
        proxy = 'String'; noproxy = 'Switch'; importfile = 'String'; ignoreunavailable = 'Switch'; ignoreversions = 'Switch'
        productcode = 'String'; allversions = 'Switch'; purge = 'Switch'; preserve = 'Switch'; includeunknown = 'Switch'; includepinned = 'Switch'
    }

    # Parameters from older versions that no longer exist, and their type
    OldParameters = @{
        WingetID = 'String'; WingetCM = 'String'; WingetOverride = 'String'; WingetScope = 'String'   # 3.x
        testverbose = 'Switch'; wait = 'Switch'                                                         # 4.0.0 - 4.0.6
        AllowRebootPassThru = 'Switch'                                                                  # 3.x - 4.0.8 (PSADT 3)
    }

    # Old name -> new name (value is kept)
    RenamedParameters = @{
        WingetID       = 'id'          # 3.x
        WingetOverride = 'override'    # 3.x
        testverbose    = 'enableverbose' # 4.0.0 - 4.0.6
    }

    # Removed without replacement
    RemovedParameters = @{
        wait = 'removed in 4.0.7 (winget --wait waits for a key press)'
        AllowRebootPassThru = 'PSADT 4 passes reboot exit codes (3010, 1641) by default; use -SuppressRebootPassThru to turn it off'
    }

    # 3.x parameters that held raw winget arguments; they are split into WingetFW parameters with WingetOptions
    WingetTextParameters = @('WingetCM', 'WingetScope')

    # Parameters that only exist in 3.x (used to detect a 3.x command line)
    V3Parameters = @('WingetID', 'WingetCM', 'WingetOverride', 'WingetScope')

    # Parameters added in 4.0.7 or later (used to detect a 4.0.7+ command line)
    V407Parameters = @('importfile', 'ignoreunavailable', 'ignoreversions', 'productcode', 'allversions', 'purge', 'preserve', 'includeunknown', 'includepinned', 'ForceRepair')

    # scope values 4.0.0 - 4.0.6 accepted but did not pass to winget; they are dropped
    RemovedScopeValues = @('Any', 'UserOrUnknown', 'SystemOrUnknown')

    # Before 4.0.7, -DeploymentType Repair always uninstalled and installed again; 4.0.7+ needs this parameter for that
    OldRepairParameter = 'ForceRepair'

    # Maps the raw winget options in 3.x -WingetCM/-WingetScope to WingetFW parameters, because 4.x only accepts WingetFW parameters.
    # Value = $true: the option takes a value. Parameter = '': dropped, WingetFW always adds it.
    WingetOptions = @{
        '--id'                                = @{ Parameter = 'id'; Value = $true }
        '--name'                              = @{ Parameter = 'name'; Value = $true }
        '--moniker'                           = @{ Parameter = 'moniker'; Value = $true }
        '-m'                                  = @{ Parameter = 'wingetmanifest'; Value = $true }
        '--manifest'                          = @{ Parameter = 'wingetmanifest'; Value = $true }
        '-v'                                  = @{ Parameter = 'version'; Value = $true }
        '--version'                           = @{ Parameter = 'version'; Value = $true }
        '-s'                                  = @{ Parameter = 'source'; Value = $true }
        '--source'                            = @{ Parameter = 'source'; Value = $true }
        '--scope'                             = @{ Parameter = 'scope'; Value = $true }
        '-a'                                  = @{ Parameter = 'architecture'; Value = $true }
        '--architecture'                      = @{ Parameter = 'architecture'; Value = $true }
        '--installer-type'                    = @{ Parameter = 'installertype'; Value = $true }
        '-e'                                  = @{ Parameter = 'exact'; Value = $false }
        '--exact'                             = @{ Parameter = 'exact'; Value = $false }
        '-i'                                  = @{ Parameter = 'interactive'; Value = $false }
        '--interactive'                       = @{ Parameter = 'interactive'; Value = $false }
        '-h'                                  = @{ Parameter = 'silent'; Value = $false }
        '--silent'                            = @{ Parameter = 'silent'; Value = $false }
        '--locale'                            = @{ Parameter = 'locale'; Value = $true }
        '-o'                                  = @{ Parameter = 'log'; Value = $true }
        '--log'                               = @{ Parameter = 'log'; Value = $true }
        '--custom'                            = @{ Parameter = 'custom'; Value = $true }
        '--override'                          = @{ Parameter = 'override'; Value = $true }
        '-l'                                  = @{ Parameter = 'location'; Value = $true }
        '--location'                          = @{ Parameter = 'location'; Value = $true }
        '--ignore-security-hash'              = @{ Parameter = 'ignoresecurityhash'; Value = $false }
        '--allow-reboot'                      = @{ Parameter = 'allowreboot'; Value = $false }
        '--skip-dependencies'                 = @{ Parameter = 'skipdependencies'; Value = $false }
        '--ignore-local-archive-malware-scan' = @{ Parameter = 'ignorelocalarchivemalwarescan'; Value = $false }
        '--dependency-source'                 = @{ Parameter = 'dependencysource'; Value = $true }
        '--no-upgrade'                        = @{ Parameter = 'noupgrade'; Value = $false }
        '--header'                            = @{ Parameter = 'header'; Value = $true }
        '--authentication-mode'               = @{ Parameter = 'authenticationmode'; Value = $true }
        '--authentication-account'            = @{ Parameter = 'authenticationaccount'; Value = $true }
        '-r'                                  = @{ Parameter = 'rename'; Value = $true }
        '--rename'                            = @{ Parameter = 'rename'; Value = $true }
        '--uninstall-previous'                = @{ Parameter = 'uninstallprevious'; Value = $false }
        '--force'                             = @{ Parameter = 'force'; Value = $false }
        '--verbose'                           = @{ Parameter = 'enableverbose'; Value = $false }
        '--verbose-logs'                      = @{ Parameter = 'enableverbose'; Value = $false }
        '--nowarn'                            = @{ Parameter = 'ignorewarnings'; Value = $false }
        '--ignore-warnings'                   = @{ Parameter = 'ignorewarnings'; Value = $false }
        '--disable-interactivity'             = @{ Parameter = 'disableinteractivity'; Value = $false }
        '--proxy'                             = @{ Parameter = 'proxy'; Value = $true }
        '--no-proxy'                          = @{ Parameter = 'noproxy'; Value = $false }
        '--product-code'                      = @{ Parameter = 'productcode'; Value = $true }
        '--all-versions'                      = @{ Parameter = 'allversions'; Value = $false }
        '--purge'                             = @{ Parameter = 'purge'; Value = $false }
        '--preserve'                          = @{ Parameter = 'preserve'; Value = $false }
        '--include-unknown'                   = @{ Parameter = 'includeunknown'; Value = $false }
        '--include-pinned'                    = @{ Parameter = 'includepinned'; Value = $false }
        '--accept-package-agreements'         = @{ Parameter = ''; Value = $false }
        '--accept-source-agreements'          = @{ Parameter = ''; Value = $false }
    }

    # Parameters that control PSADT/WingetFW and are not passed to winget (allowed with every action)
    FrameworkParameters = @('DeploymentType', 'DeployMode', 'SuppressRebootPassThru', 'TerminalServerMode', 'DisableLogging', 'Mode', 'Action', 'OverrideAPPName', 'ForceRepair', 'acceptpackageagreements', 'acceptsourceagreements')

    # Parameters that select the package (at least one is needed, 69001 otherwise)
    PackageParameters = @('wingetmanifest', 'id', 'name', 'moniker', 'productcode', 'importfile')

    # Options each winget action supports (same as $supportedOptions in Start-WinGetPackageFM)
    ActionOptions = @{
        install   = @('wingetmanifest', 'id', 'name', 'moniker', 'version', 'source', 'exact', 'enableverbose', 'ignorewarnings', 'disableinteractivity', 'proxy', 'noproxy', 'scope', 'architecture', 'installertype', 'interactive', 'silent', 'locale', 'log', 'custom', 'override', 'location', 'ignoresecurityhash', 'allowreboot', 'skipdependencies', 'ignorelocalarchivemalwarescan', 'dependencysource', 'noupgrade', 'header', 'authenticationmode', 'authenticationaccount', 'rename', 'uninstallprevious', 'force')
        uninstall = @('wingetmanifest', 'id', 'name', 'moniker', 'version', 'source', 'exact', 'enableverbose', 'ignorewarnings', 'disableinteractivity', 'proxy', 'noproxy', 'productcode', 'allversions', 'scope', 'interactive', 'silent', 'force', 'purge', 'preserve', 'log', 'header', 'authenticationmode', 'authenticationaccount')
        upgrade   = @('wingetmanifest', 'id', 'name', 'moniker', 'version', 'source', 'exact', 'enableverbose', 'ignorewarnings', 'disableinteractivity', 'proxy', 'noproxy', 'interactive', 'silent', 'purge', 'log', 'custom', 'override', 'location', 'scope', 'architecture', 'installertype', 'locale', 'ignoresecurityhash', 'allowreboot', 'skipdependencies', 'ignorelocalarchivemalwarescan', 'header', 'authenticationmode', 'authenticationaccount', 'includeunknown', 'includepinned', 'uninstallprevious', 'force')
        repair    = @('wingetmanifest', 'id', 'name', 'moniker', 'version', 'source', 'exact', 'enableverbose', 'ignorewarnings', 'disableinteractivity', 'proxy', 'noproxy', 'productcode', 'architecture', 'scope', 'interactive', 'silent', 'log', 'ignorelocalarchivemalwarescan', 'locale', 'header', 'authenticationmode', 'authenticationaccount', 'force', 'ignoresecurityhash')
        import    = @('enableverbose', 'ignorewarnings', 'disableinteractivity', 'proxy', 'noproxy', 'importfile', 'ignoreunavailable', 'ignoreversions', 'noupgrade')
    }

    # Only one parameter of each group may be used
    ConflictGroups = @(
        @('wingetmanifest', 'id', 'name', 'moniker'),
        @('interactive', 'silent', 'override'),
        @('proxy', 'noproxy'),
        @('purge', 'preserve')
    )

    # Parameter -> parameter it requires
    Requires = @{
        header = 'source'
    }
}
