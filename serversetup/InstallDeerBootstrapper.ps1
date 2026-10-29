# InstallDeerBootstrapper.ps1
# Compatible with Windows PowerShell 5.1 and PowerShell 7.


$ErrorActionPreference = 'Stop'

$Workspace = "C:\DEER"
$ScriptsPath = "C:\Scripts"

New-Item -ItemType Directory -Force -Path $Workspace
New-Item -ItemType Directory -Force -Path $ScriptsPath

$gitExe = "C:\Program Files\Git\cmd\git.exe"

# Remove any existing bootstrapper directory to ensure a clean clone
Remove-Item `
  "$Workspace\bootstrapper" `
  -Recurse `
  -Force `
  -ErrorAction SilentlyContinue

& $gitExe clone `
  --branch simularis-gh-actions `
  --single-branch `
  https://github.com/simularis/DEER-Prototypes-EnergyPlus.git `
  "$Workspace\bootstrapper"

copy-item "$Workspace\bootstrapper\scripts\BootstrapSimulation.ps1" "$ScriptsPath\BootstrapSimulation.ps1"

& $gitExe clone --branch main --single-branch https://github.com/simularis/deer-cloud-compute-setup.git "$Workspace\deer-cloud-compute-setup"
