# Requires PowerShell 7.3+ (pwsh).
param(
  [Parameter(Mandatory = $true)]
  [string]$InstanceId
)

$timestamp = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"
$createImageResponse = aws ec2 create-image `
  --instance-id $InstanceId `
  --name "deer-simulation-runner-$timestamp" `
  --description "DEER simulation runner built on $timestamp" `
  --no-reboot `
  --block-device-mappings '{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":50,"DeleteOnTermination":true}}' `
  --tag-specifications '{"Tags":[
    {"Key":"Purpose","Value":"Run DEER simulations"},
    {"Key":"EnergyPlus","Value":"9.5.0; 22.2.0"},
    {"Key":"Environment","Value":"Production"},
    {"Key":"Modelkit","Value":"0.9.3 Caboodle"},
    {"Key":"aws-cli","Value":"2.37.2"},
    {"Key":"conda","Value":"25.11.1"}
  ],"ResourceType":"image"}' `
  '{"Tags":[
    {"Key":"Purpose","Value":"Run DEER simulations"},
    {"Key":"EnergyPlus","Value":"9.5.0; 22.2.0"},
    {"Key":"Environment","Value":"Production"},
    {"Key":"Modelkit","Value":"0.9.3 Caboodle"},
    {"Key":"aws-cli","Value":"2.37.2"},
    {"Key":"conda","Value":"25.11.1"}
  ],"ResourceType":"snapshot"}' `
  --output json

if ($LASTEXITCODE -ne 0) {
  write-host $createImageResponse
  throw "aws ec2 create-image failed with exit code $LASTEXITCODE"
}

$imageId = ($createImageResponse | ConvertFrom-Json).ImageId
if (-not $imageId) {
  throw 'aws ec2 create-image did not return an ImageId'
}

Write-Output $imageId
