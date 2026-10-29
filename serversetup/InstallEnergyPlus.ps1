# InstallEnergyPlus.ps1
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

# Store the output filename into a variable for easier reference
$url1 = "https://github.com/NatLabRockies/EnergyPlus/releases/download/v9.5.0/EnergyPlus-9.5.0-de239b2e5f-Windows-x86_64.exe"
# Update the expected hash value from the downloads page, see sha256sum.txt in the release assets.
# The hash value below is for the 9.5.0 release as of 2021-05-05.
$checksum1 = "b3b1b70451958d6879d97f5111bb8e6cca3843478afbba2fabca7c0ad6e245df"
$energyPlus950 = split-path $url1 -leaf

if (Test-Path "C:\EnergyPlusV9-5-0\energyplus.exe") {
    Write-Host "EnergyPlus 9.5 already installed."
}
else {
    # Download and install EnergyPlus 9.5.0
    invoke-webrequest -Uri $url1 -OutFile $energyPlus950
    # Raise an error if the hash does not match
    if ((Get-FileHash -Algorithm SHA256 $energyPlus950).Hash.ToLower() -ne $checksum1) {
        throw "Hash mismatch for EnergyPlus-9.5.0"
    } 
    else {
        # first attempt at command line install, but pauses for interactive input.
        #& ".\$energyPlus950" in
        # second attempt at command line install, but stops with installer error while trying to copy to C:\Windows\SysWOW64\MSCOMCTL.OCX.
        #& ".\$energyPlus950" in --am --al --c
        # third attempt at command line install, but still stops with installer error while trying to copy to C:\Windows\SysWOW64\MSCOMCTL.OCX.
        start-process -filepath $energyPlus950 -ArgumentList "in --am --al --c" -verb runas
    }
}

$url2 = "https://github.com/NatLabRockies/EnergyPlus/releases/download/v22.2.0/EnergyPlus-22.2.0-c249759bad-Windows-x86_64.exe"
# Update the expected hash value from the downloads page, see sha256sum.txt in the release assets.
# The hash value below is for the 22.2.0 release as of 2022-09-30.
$checksum2 = "28fb4dd43756df92c02972b41af28d05cf0e44bbad5ee7822ae1b019120ea853"
$energyPlus2220 = split-path $url2 -leaf

if (Test-Path "C:\EnergyPlusV22-2-0\energyplus.exe") {
    Write-Host "EnergyPlus 22.2.0 already installed."
}
else {
    invoke-webrequest -Uri $url2 -OutFile $energyPlus2220
    # confirm hash is correct before running the installer
    if ((Get-FileHash -Algorithm SHA256 $energyPlus2220).Hash.ToLower() -ne $checksum2) {
        throw "Hash mismatch for EnergyPlus-22.2.0"
    }
    else {
        & ".\$energyPlus2220" in --am --al --c
    }
}
