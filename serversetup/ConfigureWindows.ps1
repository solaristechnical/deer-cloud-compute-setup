# ConfigureWindows.ps1
# Compatible with Windows PowerShell 5.1 and PowerShell 7; installs pwsh, so it must run under 5.1 on a new server.

New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force

winget install --id Microsoft.PowerShell --source winget --scope machine --installer-type wix
