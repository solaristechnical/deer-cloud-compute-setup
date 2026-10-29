# Install-AwsCli.ps1
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

if (Get-Command aws -ErrorAction SilentlyContinue) {
    Write-Host "AWS CLI already installed."
    return
}

msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi /qn

# Future improvements: convert workflow scripts to use AWS.Tools modules instead of the AWS CLI.
#Install-Module AWS.Tools.Installer
