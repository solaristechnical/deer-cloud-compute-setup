# Install-Anaconda.ps1
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

# Option 1. If Anaconda is not actually required, we can install Python 3.14 directly using winget and pip.
#winget install Python.Python.3.14
#pip install --upgrade pip
#pip install -r requirements.txt

# Option 2. If pip is not sufficient, we could switch to Anaconda.

$condaExe = "C:\ProgramData\Anaconda3\Scripts\conda.exe"

if (Test-Path $condaExe) {
    Write-Host "Anaconda already installed."
}
else {
    winget install -e --id Anaconda.Anaconda3 --source winget --scope machine --override "/InstallationType=AllUsers /S /D=C:\ProgramData\Anaconda3"

}

if (-not (Test-Path $condaExe)) {
    throw "Conda executable not found at $condaExe"
}

& $condaExe tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main
& $condaExe tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r
& $condaExe tos accept --override-channels --channel https://repo.anaconda.com/pkgs/msys2

# Optionally, we could initialize conda for PowerShell, but this is not strictly necessary for running Python scripts.
# & $condaExe init powershell

# Create a new conda environment for Python 3.14 and install the required packages.
$EnvExists = & $condaExe env list |
    Select-String "py314"

if (-not $EnvExists) {
    & $condaExe create -y -n py314 python=3.14
}
& $condaExe run -n py314 pip install --upgrade pip
& $condaExe run -n py314 pip install -r requirements.txt
