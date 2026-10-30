# Requires Windows PowerShell 5.1; no winget, desktop, or elevation prompts.
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('PowerShell', 'Git', 'AwsCli', 'EnergyPlus', 'Modelkit', 'Anaconda')]
    [string]$Component
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$DownloadDirectory = Join-Path $env:TEMP "deer-install-$Component"
New-Item -ItemType Directory -Path $DownloadDirectory -Force | Out-Null

function Get-Installer {
    param(
        [string]$Uri,
        [string]$Name,
        [string]$Sha256
    )

    $path = Join-Path $DownloadDirectory $Name
    Write-Host "Downloading $Uri"
    Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $path
    if ($Sha256) {
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $Sha256) {
            throw "SHA256 mismatch for $Name"
        }
    }
    else {
        # AWS publishes this MSI at a rolling URL; require a trusted signature.
        $signature = Get-AuthenticodeSignature -LiteralPath $path
        if ($signature.Status -ne 'Valid') {
            throw "Invalid Authenticode signature for ${Name}: $($signature.Status)"
        }
    }
    return $path
}

function Invoke-Installer {
    param(
        [string]$FilePath,
        [string]$Arguments
    )

    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -notin @(0, 3010)) {
        throw "$FilePath failed with exit code $($process.ExitCode)"
    }
}

function Invoke-Conda {
    param([string[]]$CondaArguments)

    & 'C:\ProgramData\Anaconda3\Scripts\conda.exe' @CondaArguments
    if ($LASTEXITCODE -ne 0) {
        throw "conda $($CondaArguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

try {
    switch ($Component) {
        'PowerShell' {
            $installer = Get-Installer `
                -Uri 'https://github.com/PowerShell/PowerShell/releases/download/v7.4.13/PowerShell-7.4.13-win-x64.msi' `
                -Name 'PowerShell.msi' `
                -Sha256 'b5c32ec7902748648624f97c70a6d5637d93e9db4f21f9713868d7933e419efb'
            Invoke-Installer msiexec.exe "/i `"$installer`" /qn /norestart ADD_PATH=1 ENABLE_MU=0 USE_MU=0"
        }
        'Git' {
            $installer = Get-Installer `
                -Uri 'https://github.com/git-for-windows/git/releases/download/v2.56.0.windows.4/Git-2.56.0.4-64-bit.exe' `
                -Name 'Git.exe' `
                -Sha256 '4961a4a8cc778d8b6e00a5819e5fe4d078b754555aff7aedc2d77a5d74c2de80'
            Invoke-Installer $installer '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /ALLUSERS /o:PathOption=Cmd'
            & 'C:\Program Files\Git\cmd\git.exe' config --system core.longpaths true
            if ($LASTEXITCODE -ne 0) {
                throw "Git long-path configuration failed with exit code $LASTEXITCODE"
            }
        }
        'AwsCli' {
            $installer = Get-Installer -Uri 'https://awscli.amazonaws.com/AWSCLIV2.msi' -Name 'AWSCLIV2.msi'
            Invoke-Installer msiexec.exe "/i `"$installer`" /qn /norestart"
        }
        'EnergyPlus' {
            $releases = @(
                @{
                    Version = '9.5.0'
                    Build = 'de239b2e5f'
                    Sha256 = '0fbdebef1223c4d9ddc3560dbd7042995097e9e668f68b8510302952d3d8ffb6'
                    Destination = 'C:\EnergyPlusV9-5-0'
                },
                @{
                    Version = '22.2.0'
                    Build = 'c249759bad'
                    Sha256 = '89d8b3bd7979cbaf214b4381beef9d4b1b6ecbd4c8d23e535ab5bb21af557c5d'
                    Destination = 'C:\EnergyPlusV22-2-0'
                }
            )
            foreach ($release in $releases) {
                $name = "EnergyPlus-$($release.Version)-$($release.Build)-Windows-x86_64.zip"
                $archive = Get-Installer `
                    -Uri "https://github.com/NatLabRockies/EnergyPlus/releases/download/v$($release.Version)/$name" `
                    -Name $name -Sha256 $release.Sha256
                $staging = Join-Path $DownloadDirectory $release.Version
                Expand-Archive -LiteralPath $archive -DestinationPath $staging
                $executables = @(Get-ChildItem -LiteralPath $staging -Filter energyplus.exe -Recurse -File)
                if ($executables.Count -ne 1) {
                    throw "Expected one energyplus.exe in $name, found $($executables.Count)"
                }
                Move-Item -LiteralPath $executables[0].Directory.FullName -Destination $release.Destination
            }
        }
        'Modelkit' {
            $installer = Get-Installer `
                -Uri 'https://share.bigladdersoftware.com/files/modelkit-caboodle-0.9.3+59d2aa1.exe' `
                -Name 'Modelkit.exe' `
                -Sha256 '2cbbba81de5fb4c1350147c262975080d27934822d9a29d09ba63b8742155eef'
            Invoke-Installer $installer '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /DIR=C:\Modelkit'
        }
        'Anaconda' {
            $installer = Get-Installer `
                -Uri 'https://repo.anaconda.com/archive/Anaconda3-2026.07-1-Windows-x86_64.exe' `
                -Name 'Anaconda.exe' `
                -Sha256 'b545f4bd8ab3bf32d99002a0779a887668ebfe479ee32ecbf060375670d5ee09'
            # NSIS requires /D to be the final argument and its path to be unquoted.
            Invoke-Installer $installer '/InstallationType=AllUsers /RegisterPython=0 /AddToPath=0 /S /D=C:\ProgramData\Anaconda3'
            foreach ($channel in @('main', 'r', 'msys2')) {
                Invoke-Conda @('tos', 'accept', '--override-channels', '--channel', "https://repo.anaconda.com/pkgs/$channel")
            }
            Invoke-Conda @('create', '--yes', '--name', 'py314', 'python=3.14')
            Invoke-Conda @('run', '--name', 'py314', 'python', '-m', 'pip', 'install', '--upgrade', 'pip')
            Invoke-Conda @('run', '--name', 'py314', 'python', '-m', 'pip', 'install', '--no-cache-dir', '-r', (Join-Path $PSScriptRoot 'requirements.txt'))
            Invoke-Conda @('clean', '--all', '--yes')
        }
    }
}
finally {
    Remove-Item -LiteralPath $DownloadDirectory -Recurse -Force
}
