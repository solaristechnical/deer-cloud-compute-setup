# Install-All.ps1
# Compatible with Windows PowerShell 5.1 and PowerShell 7; run as Administrator on a new server.

$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent $PSCommandPath

& "$ScriptRoot\ConfigureWindows.ps1"
& "$ScriptRoot\Install-SSMAgent.ps1"
& "$ScriptRoot\Install-AwsCli.ps1"
& "$ScriptRoot\InstallEnergyPlus.ps1"
& "$ScriptRoot\InstallModelkit.ps1"
& "$ScriptRoot\Install-Git.ps1"

# Reload Machine Path
$MachinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
# Reload User Path
$UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
# Combine and update the current session
$env:Path = "$MachinePath;$UserPath"

& "$ScriptRoot\InstallDeerBootstrapper.ps1"
& "$ScriptRoot\Install-Anaconda.ps1"

$MachinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$env:Path = "$MachinePath;$UserPath"

& "$ScriptRoot\Test-Environment.ps1"
