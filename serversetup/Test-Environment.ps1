# Test-Environment.ps1
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

# Conduct all the tests and collect pass/fail results.
# Then, write a summary to output.
$TestResults = @{}

# Confirm which version of PowerShell is being used
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Cyan

# Test the environment to make sure we can use Git, modelkit, energyplus, and aws ssm agent, etc.
if (Get-Service -Name "AmazonSSMAgent" -ErrorAction SilentlyContinue) {
    Write-Host "AWS SSM Agent is installed." -ForegroundColor Green
    $TestResults["AWS SSM Agent"] = $true
    
    # Optional: Check if it's currently running
    $status = (Get-Service -Name "AmazonSSMAgent").Status
    Write-Host "Current Status: $status"
} else {
    Write-Host "AWS SSM Agent is NOT installed." -ForegroundColor Red
    $TestResults["AWS SSM Agent"] = $false
}

$AwsCli = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"

if (-not (Test-Path $AwsCli)) {
    $TestResults["AWS CLI"] = $false
    Write-Host "AWS CLI not found at $AwsCli" -ForegroundColor Red
} else {
    $TestResults["AWS CLI"] = $true
    Write-Host "AWS CLI found at the expected location: $AwsCli" -ForegroundColor Green
}

try {
    & $AwsCli --version
    $TestResults["AWS CLI Version"] = $true
} catch {
    Write-Host "Failed to get AWS CLI version." -ForegroundColor Red
    $TestResults["AWS CLI Version"] = $false
}

try {
    git --version
    $TestResults["Git Version"] = $true
} catch {
    Write-Host "Failed to get Git version." -ForegroundColor Red
    $TestResults["Git Version"] = $false
}

if (Test-Path "C:\EnergyPlusV9-5-0\EnergyPlus.exe") {
    try {
        & "C:\EnergyPlusV9-5-0\EnergyPlus.exe" --version
        $TestResults["EnergyPlusV9-5-0 Version"] = $true
    } catch {
        Write-Host "Failed to get EnergyPlusV9-5-0 version." -ForegroundColor Red
        $TestResults["EnergyPlusV9-5-0 Version"] = $false
    }
} else {
    Write-Host "[Fail] EnergyPlusV9-5-0 not found." -ForegroundColor Red
    $TestResults["EnergyPlusV9-5-0 Version"] = $false
}
if (Test-Path "C:\EnergyPlusV22-2-0\EnergyPlus.exe") {
    try {
        & "C:\EnergyPlusV22-2-0\EnergyPlus.exe" --version
        $TestResults["EnergyPlusV22-2-0 Version"] = $true
    } catch {
        Write-Host "Failed to get EnergyPlusV22-2-0 version." -ForegroundColor Red
        $TestResults["EnergyPlusV22-2-0 Version"] = $false
    }
} else {
    Write-Host "[Fail] EnergyPlusV22-2-0 not found." -ForegroundColor Red
    $TestResults["EnergyPlusV22-2-0 Version"] = $false
}

try {
    modelkit --version
    $TestResults["ModelKit Version"] = $true
} catch {
    Write-Host "Failed to get ModelKit version." -ForegroundColor Red
    $TestResults["ModelKit Version"] = $false
}

$CondaExe = "C:\ProgramData\Anaconda3\Scripts\conda.exe"
if (-not (Test-Path $CondaExe)) {
    $TestResults["Conda"] = $false
    Write-Host "Conda not found at $CondaExe" -ForegroundColor Red
} else {
    $TestResults["Conda"] = $true
    Write-Host "Conda found at the expected location: $CondaExe" -ForegroundColor Green
}
try {
    & $CondaExe --version
    $TestResults["Conda Version"] = $true
} catch {
    Write-Host "Failed to get Conda version." -ForegroundColor Red
    $TestResults["Conda Version"] = $false
}
# Confirm that the py314 Conda environment exists and can run Python.
try {
    & $CondaExe env list | Select-String "py314"
    $TestResults["py314 Environment Exists"] = $true
} catch {
    Write-Host "Failed to find py314 Conda environment." -ForegroundColor Red
    $TestResults["py314 Environment Exists"] = $false
}

try {
    & $CondaExe run -n py314 python --version
    $TestResults["py314 Python Version"] = $true
} catch {
    Write-Host "Failed to run Python in py314 Conda environment." -ForegroundColor Red
    $TestResults["py314 Python Version"] = $false
}

# Check if OS is Windows
# if $isWindows is not defined, define it based on the current platform.
if (-not (Get-Variable -Name isWindows -Scope Script -ErrorAction SilentlyContinue)) {
    # If this is PowerShell 5.1, PSVersionTable.PSPlatform might return null
    if (-not $PSVersionTable.PSPlatform) {    
        $isWindows = $env:OS -eq "Windows_NT"
    } else {
        $isWindows = $PSVersionTable.PSPlatform -eq 'Win32NT'
    }
}
$TestResults["OS is Windows"] = $isWindows

# Test LongPathsEnabled
try {
    $LongPathsEnabled = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -ErrorAction SilentlyContinue
    if ($LongPathsEnabled.LongPathsEnabled -eq 1) {
        Write-Host "LongPathsEnabled is enabled in Windows registry." -ForegroundColor Green
        $TestResults["LongPathsEnabled"] = $true
    } else {
        Write-Host "LongPathsEnabled is NOT enabled in Windows registry." -ForegroundColor Red
        $TestResults["LongPathsEnabled"] = $false
    }
} catch {
    Write-Host "LongPathsEnabled test skipped because the platform is not Windows." -ForegroundColor Yellow
    $TestResults["LongPathsEnabled"] = $false
}

# Write a file with a long path to confirm that LongPathsEnabled is actually working.
$drive = "C:\"
$longDir = Join-Path (join-path (join-path $drive "Temp\") ("a" * 130)) ("b" * 130)
$longPath = Join-Path $longDir "test.txt"
#$longPath = "\\?\C:\Temp\" + ("a" * 260) + "\test.txt"
try {
    New-Item -ItemType File -Path $longPath -Force -ErrorAction Stop | Out-Null
    Write-Host "Successfully created a file with a long path." -ForegroundColor Green
    Remove-Item -Path $longPath -Force
    Remove-Item -Path $longDir -Force
    $TestResults["LongPathsTest"] = $true
} catch {
    Write-Host "Failed to create a file with a long path." -ForegroundColor Red
    $_ | Format-List -Force
    $TestResults["LongPathsTest"] = $false
}

# Write a summary message and return an appropriate exit code.
Write-Host "`nTest Summary:" -ForegroundColor Cyan
foreach ($key in $TestResults.Keys) {
    if ($TestResults[$key]) {
        Write-Host "[Pass] $key" -ForegroundColor Green
    } else {
        Write-Host "[Fail] $key" -ForegroundColor Red
    }
}

if ($TestResults.Values -contains $false) {
    exit 1
} else {
    exit 0
}

# End of environment tests