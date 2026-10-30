# escape=`
FROM mcr.microsoft.com/windows/servercore:ltsc2022

SHELL ["powershell.exe", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]
USER ContainerAdministrator

COPY ["docker\\windows\\Install-Container.ps1", "C:\\container\\Install-Container.ps1"]
COPY ["serversetup\\requirements.txt", "C:\\container\\requirements.txt"]

RUN $ErrorActionPreference = 'Stop'; `
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -Value 1 -PropertyType DWORD -Force | Out-Null; `
    & C:\container\Install-Container.ps1 -Component PowerShell
RUN C:\container\Install-Container.ps1 -Component Git
RUN C:\container\Install-Container.ps1 -Component AwsCli
RUN C:\container\Install-Container.ps1 -Component EnergyPlus
RUN C:\container\Install-Container.ps1 -Component Modelkit
RUN C:\container\Install-Container.ps1 -Component Anaconda

# Windows base-image PATH is not reliably available to Docker ENV expansion.
ENV PATH="C:\Program Files\PowerShell\7;C:\Program Files\Git\cmd;C:\Program Files\Amazon\AWSCLIV2;C:\Modelkit\bin;C:\ProgramData\Anaconda3;C:\ProgramData\Anaconda3\Scripts;C:\Windows\System32;C:\Windows;C:\Windows\System32\Wbem;C:\Windows\System32\WindowsPowerShell\v1.0"
SHELL ["C:\\Program Files\\PowerShell\\7\\pwsh.exe", "-NoLogo", "-NoProfile", "-Command"]

COPY ["workflow", "C:\\DEER\\deer-cloud-compute-setup\\workflow\\"]
COPY ["docker\\windows\\Test-Container.ps1", "C:\\container\\Test-Container.ps1"]
RUN $ErrorActionPreference = 'Stop'; `
    New-Item -ItemType Directory -Path C:\Scripts, C:\githubactions -Force | Out-Null; `
    Copy-Item C:\DEER\deer-cloud-compute-setup\workflow\BootstrapSimulation.ps1 C:\Scripts\BootstrapSimulation.ps1; `
    & C:\container\Test-Container.ps1

WORKDIR C:\githubactions
CMD ["C:\\Program Files\\PowerShell\\7\\pwsh.exe", "-NoLogo", "-NoProfile"]
