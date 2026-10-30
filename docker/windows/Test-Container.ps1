# Run during docker build and on demand inside the container.
#Requires -Version 7.3
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version Latest

function Assert-NativeCommand {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$ExpectedOutput
    )

    $output = & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE"
    }
    $output | Write-Host
    if ($ExpectedOutput -and ($output -join "`n") -notmatch $ExpectedOutput) {
        throw "$FilePath did not report the expected output: $ExpectedOutput"
    }
}

if (-not $IsWindows) {
    throw 'This image requires Windows.'
}

Assert-NativeCommand 'pwsh.exe' @('-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()') '^7\.'
Assert-NativeCommand 'powershell.exe' @('-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()') '^5\.1\.'
Assert-NativeCommand 'chcp.com' @()
Assert-NativeCommand 'git.exe' @('--version') 'git version'
Assert-NativeCommand 'git.exe' @('config', '--system', '--get', 'core.longpaths') '^true$'
Assert-NativeCommand 'aws.exe' @('--version') 'aws-cli/2\.'
Assert-NativeCommand 'C:\EnergyPlusV9-5-0\energyplus.exe' @('--version') '9\.5\.0'
Assert-NativeCommand 'C:\EnergyPlusV22-2-0\energyplus.exe' @('--version') '22\.2\.0'
Assert-NativeCommand 'modelkit.bat' @('--version')
if ((Get-Content -LiteralPath 'C:\Modelkit\version' -Raw).Trim() -ne '0.9.3+59d2aa1') {
    throw 'Unexpected Modelkit Caboodle version.'
}

$conda = 'C:\ProgramData\Anaconda3\Scripts\conda.exe'
Assert-NativeCommand $conda @('--version') 'conda '
Assert-NativeCommand $conda @('run', '-n', 'py314', 'python', '--version') 'Python 3\.14\.'
Assert-NativeCommand $conda @('run', '-n', 'py314', 'python', '-m', 'pip', 'check')
Assert-NativeCommand $conda @(
    'run', '-n', 'py314', 'python', '-c',
    'import pandas, numpy, openpyxl, bs4, xlsxwriter, lxml.etree, matplotlib, tqdm, plotly; print(''Python dependencies OK'')'
) 'Python dependencies OK'

foreach ($path in @(
    'C:\Scripts\BootstrapSimulation.ps1',
    'C:\DEER\deer-cloud-compute-setup\workflow\BootstrapSimulation.ps1',
    'C:\DEER\deer-cloud-compute-setup\workflow\Workflow.psm1',
    'C:\githubactions'
)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required workflow path is missing: $path"
    }
}
Import-Module 'C:\DEER\deer-cloud-compute-setup\workflow\Workflow.psm1' -Force
Get-Command Invoke-DEERWorkflowController -ErrorAction Stop | Out-Null

$longPaths = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled
if ($longPaths -ne 1) {
    throw 'Windows long-path support is not enabled.'
}
$testRoot = Join-Path $env:TEMP ("deer-long-path-" + [guid]::NewGuid().ToString('N'))
try {
    $directory = Join-Path (Join-Path $testRoot ('a' * 130)) ('b' * 130)
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $testFile = Join-Path $directory 'test.txt'
    Set-Content -LiteralPath $testFile -Value 'long-path test'
    if ((Get-Content -LiteralPath $testFile) -ne 'long-path test') {
        throw 'Long-path file round-trip failed.'
    }
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
Write-Host 'Container environment checks passed.'
