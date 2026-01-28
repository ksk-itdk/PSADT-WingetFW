$ErrorActionPreference = "SilentlyContinue"

$AppName = "VCE Exam Simulator"
$AppVersion = "0"


$Apps = (Get-ChildItem HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\) | Get-ItemProperty | Select-Object DisplayName, @{Name='DisplayVersion'; Expression={if ($_.DisplayVersion) {$_.DisplayVersion} else {'0'}}}
$Apps += (Get-ChildItem HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\) | Get-ItemProperty | Select-Object DisplayName, @{Name='DisplayVersion'; Expression={if ($_.DisplayVersion) {$_.DisplayVersion} else {'0'}}}


$AppFound = $Apps | Where-Object {
($_.DisplayName -like $AppName) -and (($(if($_.DisplayVersion -eq 0){$_.DisplayVersion}else{[version]$_.DisplayVersion}) -replace '[a-zA-Z-]','') -ge $(if($AppVersion -eq 0){$AppVersion}else{[version]$AppVersion}))
}

if ($AppFound) 
{Write-Output "Installed"}
