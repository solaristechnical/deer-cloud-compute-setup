# Install-SSMAgent.ps1
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

# Install the AWS Systems Manager Agent (SSM Agent) on Windows Server 2022.

# Install-SSMAgent.ps1

$service = Get-Service -Name AmazonSSMAgent -ErrorAction SilentlyContinue

if ($service) {
    Write-Host "Amazon SSM Agent is already installed."

    Set-Service AmazonSSMAgent -StartupType Automatic

    if ($service.Status -ne 'Running') {
        Start-Service AmazonSSMAgent
    }

    return
}

Write-Host "Installing Amazon SSM Agent..."

# Create a temporary directory for the installer
$dir = Join-Path $env:TEMP "ssm"
New-Item -ItemType Directory -Path $dir -Force | Out-Null
Set-Location $dir

# Download the latest Amazon SSM Agent installer
$installerUrl = "https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/windows_amd64/AmazonSSMAgentSetup.exe"

Invoke-WebRequest `
    -Uri $installerUrl `
    -OutFile "AmazonSSMAgentSetup.exe"

# Install the agent silently and wait for it to complete
Start-Process `
    .\AmazonSSMAgentSetup.exe `
    -ArgumentList @("/q", "/log", "install.log") `
    -Wait

Set-Service AmazonSSMAgent -StartupType Automatic
Start-Service AmazonSSMAgent

if ((Get-Service AmazonSSMAgent).Status -ne 'Running') {
    throw "Amazon SSM Agent installation failed."
}
