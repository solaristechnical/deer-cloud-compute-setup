# Requires PowerShell 7.3+ (pwsh); ConvertFrom-Json -AsHashtable is not available in Windows PowerShell 5.1.
param(
    [Parameter(Mandatory = $true)]
    [string]$ImageId,

    [string]$LaunchTemplateId = $env:EC2_LAUNCH_TEMPLATE_ID
)

foreach ($name in @('EC2_KEY_PAIR_NAME', 'SECURITY_GROUP_ID', 'EC2_INSTANCE_PROFILE_ARN')) {
    if (-not (Get-Item -Path "Env:$name" -ErrorAction SilentlyContinue).Value) {
        throw "Required environment variable $name is not set."
    }
}
if (-not $LaunchTemplateId) {
    throw 'Set EC2_LAUNCH_TEMPLATE_ID or pass -LaunchTemplateId.'
}

$launchTemplateData = @'
{
    "KeyName":"",
    "ImageId":"",
    "InstanceType":"c8in.xlarge",
    "MetadataOptions":{"HttpPutResponseHopLimit":2},
    "TagSpecifications":[
        {
            "ResourceType":"instance",
            "Tags":[
                {"Key":"ManagedBy","Value":"GitHubActions"},
                {"Key":"Workload","Value":"RunDeerSimulations"}
            ]
        },
        {
            "ResourceType":"volume",
            "Tags":[
                {"Key":"ManagedBy","Value":"GitHubActions"},
                {"Key":"Workload","Value":"RunDeerSimulations"}
            ]
        },
        {
            "ResourceType":"network-interface",
            "Tags":[
                {"Key":"ManagedBy","Value":"GitHubActions"},
                {"Key":"Workload","Value":"RunDeerSimulations"}
            ]
        }
    ],
    "NetworkInterfaces":[
        {"AssociatePublicIpAddress":true,"DeviceIndex":0,"Groups":[]}
    ],
    "BlockDeviceMappings":[
        {"DeviceName":"/dev/sda1","Ebs":{"Encrypted":true,"DeleteOnTermination":true,"Iops":3000,"VolumeSize":100,"VolumeType":"gp3","Throughput":125}}
    ],
    "IamInstanceProfile":{"Arn":""}}
'@ | ConvertFrom-Json -AsHashtable

$launchTemplateData.KeyName = $env:EC2_KEY_PAIR_NAME
$launchTemplateData.NetworkInterfaces[0].Groups = @($env:SECURITY_GROUP_ID)
$launchTemplateData.IamInstanceProfile.Arn = $env:EC2_INSTANCE_PROFILE_ARN
$launchTemplateData.ImageId = $ImageId
$launchTemplateJson = ConvertTo-Json -InputObject $launchTemplateData -Depth 100 -Compress

$timestamp = Get-Date -Format "yyyy-MM-dd"
$createVersionResponse = aws ec2 create-launch-template-version `
    --launch-template-id $LaunchTemplateId `
    --version-description "DEER simulation runner built on $timestamp with configured instance profile and network settings" `
    --launch-template-data $launchTemplateJson `
    --output json

if ($LASTEXITCODE -ne 0) {
    Write-Host $createVersionResponse
    throw "aws ec2 create-launch-template-version failed with exit code $LASTEXITCODE"
}

Write-Output $createVersionResponse
