# WingetFW 5.0.0 - Exit codes and logs

[Back to README](../README.md)

## EXIT CODES
| Exit code | Meaning |
|---|---|
| 0 | Success. With install, also when the package is already installed (winget `0x8A150061` or `0x8A15002B`); the log says "is already installed, nothing to install". |
| 1641, 3010 | Success, a reboot is required. Passed to Intune unless `-SuppressRebootPassThru` is used. |
| 60001 | An option rule was broken (see [OPTION RULES](Parameters.md#option-rules)), a source is not in `AllowedSources` (see [Configuration](Configuration.md)), a mod file was refused or failed (see [Mod files](Mods.md)), or another error occurred. The reason is in the log. |
| 60008 | PSAppDeployToolkit could not start (module or session). |
| 69001 | No package specified. Use `-id`, `-name`, `-moniker`, `-wingetmanifest`, `-productcode` or `-importfile`. |
| 69002 | Skipped by a mod file: a Pre section returned `$false`, winget did not run. |
| Other | The winget return code is passed through, for example `-1978335212` (`0x8A150014`, no installed package found). See [winget return codes](https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md). |

## LOG FILE
| Mode | Log file |
|---|---|
| Admin | `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\<OverrideAPPName\|id\|name>_WingetFW_<version>_EN_01_PSAppDeployToolkit_<DeploymentType>.log` |
| User | `C:\ProgramData\Logs\Software\<OverrideAPPName\|id\|name>_WingetFW_<version>_EN_01_PSAppDeployToolkit_<DeploymentType>_<user name>.log` |

The folders are `LogPath` and `LogPathNoAdminRights` in `Config\config.psd1`. The log contains the WingetFW parameters, the final winget command line, winget's output and the winget exit code. Use `-OverrideAPPName` to change the first part of the file name. Use `-log` for winget's own log file.
