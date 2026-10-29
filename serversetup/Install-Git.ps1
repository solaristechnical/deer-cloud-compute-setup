# Install-Git.ps1
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Host "Git already installed."
    return
}
winget install --id Git.Git -e --source winget

# Add Git to the system PATH and enable long paths
$gitExe = "C:\Program Files\Git\cmd\git.exe"
& $gitExe config --system core.longpaths true
