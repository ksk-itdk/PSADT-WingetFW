$ErrorActionPreference = "SilentlyContinue"

$AppName = "NVM for Windows*"
$AppVersion = "1.2.2" 


$Apps = (Get-ChildItem HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\) | Get-ItemProperty | select DisplayName, DisplayVersion
$Apps += (Get-ChildItem HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\) | Get-ItemProperty | select DisplayName, DisplayVersion


$AppFound = $Apps | Where-Object {
($_.DisplayName -like $AppName) -and ([version]($_.DisplayVersion -replace '[a-zA-Z-]','') -ge [version]$AppVersion)
}

if ($AppFound) 
{Write-Output "Installed"}
