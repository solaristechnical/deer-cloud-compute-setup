# InstallModelkit.ps1
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

$url = "https://share.bigladdersoftware.com/files/modelkit-caboodle-0.9.3+59d2aa1.exe"
$checksum = "2cbbba81de5fb4c1350147c262975080d27934822d9a29d09ba63b8742155eef"
$modelkit_installer = split-path $url -leaf

if (Get-Command modelkit -ErrorAction SilentlyContinue) {
    Write-Host "Modelkit already installed."
    return
} else {
    Write-Host "Installing Modelkit..."
    #invoke-webrequest -Uri $url -OutFile $modelkit_installer
    curl.exe -C - -o $modelkit_installer $url
    if ((Get-FileHash -Algorithm SHA256 $modelkit_installer).Hash.ToLower() -ne $checksum) {
        throw "Hash mismatch for Modelkit"
    }
    else {
        & ".\$modelkit_installer" /SP
    }
    Write-Host "Modelkit installation complete."
}
