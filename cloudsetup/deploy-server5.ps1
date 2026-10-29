<#
.SYNOPSIS
Uploads the current repository commit and deploys it to the server5 EC2 instance.

.DESCRIPTION
Requires PowerShell 7.3+ (pwsh), Git, AWS CLI, and AWS credentials with access to the deployment S3 bucket,
EC2, and Systems Manager. Local runs deploy HEAD; uncommitted changes are excluded.

.EXAMPLE
./cloudsetup/deploy-server5.ps1

.EXAMPLE
./cloudsetup/deploy-server5.ps1 -AwsRegion us-west-2 -DeployBucket my-deploy-bucket
#>
param(
    [string]$AwsRegion = $(if ($env:AWS_REGION) { $env:AWS_REGION } else { 'us-east-1' }),
    [string]$DeployBucket = $env:DEPLOY_BUCKET,
    [string]$DeploymentId = $(if ($env:GITHUB_RUN_ID) { "$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT" } else { "local-$([Guid]::NewGuid().ToString('N'))" })
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

function Invoke-Aws {
    $output = & aws @args
    if ($LASTEXITCODE -ne 0) { throw "AWS CLI failed: $($args -join ' ')" }
    return $output
}

if ([string]::IsNullOrWhiteSpace($DeployBucket)) {
    throw 'Set DEPLOY_BUCKET or pass -DeployBucket.'
}
if ($DeployBucket -notmatch '^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$') {
    throw 'DeployBucket must be an S3 bucket name.'
}
if ($AwsRegion -notmatch '^[a-z0-9-]+$') {
    throw 'AwsRegion must be an AWS region name.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$commit = & git -C $repoRoot rev-parse HEAD
$archive = Join-Path ([System.IO.Path]::GetTempPath()) "repository-$([Guid]::NewGuid().ToString('N')).zip"
& git -C $repoRoot archive --format=zip "--output=$archive" HEAD
$s3Uri = "s3://$DeployBucket/githubactions/deploy-server5/$DeploymentId/$commit.zip"
Invoke-Aws s3 cp $archive $s3Uri --only-show-errors

$instanceIds = @(Invoke-Aws ec2 describe-instances `
    --filters 'Name=tag:Name,Values=server5' 'Name=instance-state-name,Values=pending,running,stopping,stopped' `
    --query 'Reservations[].Instances[].InstanceId' --output json | ConvertFrom-Json)
if ($instanceIds.Count -ne 1) {
    throw "Expected exactly one server5 instance; found $($instanceIds.Count)."
}
$instanceId = $instanceIds[0]
$state = Invoke-Aws ec2 describe-instances --instance-ids $instanceId `
    --query 'Reservations[0].Instances[0].State.Name' --output text
if ($state -eq 'stopping') {
    Invoke-Aws ec2 wait instance-stopped --instance-ids $instanceId
}
Invoke-Aws ec2 start-instances --instance-ids $instanceId
Invoke-Aws ec2 wait instance-running --instance-ids $instanceId

$ready = $false
$deadline = (Get-Date).AddMinutes(10)
do {
    $ping = Invoke-Aws ssm describe-instance-information `
        --filters "Key=InstanceIds,Values=$instanceId" `
        --query 'InstanceInformationList[0].PingStatus' --output text
    if ($ping -eq 'Online') {
        $ready = $true
        break
    }
    Start-Sleep -Seconds 10
} while ((Get-Date) -lt $deadline)
if (-not $ready) { throw "SSM did not become online for $instanceId within 10 minutes." }

$remoteScript = @'
$ErrorActionPreference = 'Stop'
$repoDir = 'C:\DEER\deer-cloud-compute-setup'
$deployId = [Guid]::NewGuid().ToString('N')
$archive = Join-Path $env:TEMP "$deployId.zip"
$stagingDir = "C:\DEER\deer-cloud-compute-setup-staging-$deployId"
$backupDir = "C:\DEER\deer-cloud-compute-setup-backup-$deployId"
try {
    New-Item -ItemType Directory -Path 'C:\DEER' -Force | Out-Null
    & aws s3 cp '__S3_URI__' $archive --region '__AWS_REGION__' --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw 'Failed to download deployment archive.' }
    Expand-Archive -LiteralPath $archive -DestinationPath $stagingDir -Force
    if (-not (Test-Path -LiteralPath (Join-Path $stagingDir 'workflow\Workflow.psm1'))) {
        throw 'Archive does not contain the expected repository files.'
    }
    if (Test-Path -LiteralPath $repoDir) {
        Move-Item -LiteralPath $repoDir -Destination $backupDir
    }
    try {
        Move-Item -LiteralPath $stagingDir -Destination $repoDir
    } catch {
        if (Test-Path -LiteralPath $backupDir) {
            Move-Item -LiteralPath $backupDir -Destination $repoDir
        }
        throw
    }
    if (Test-Path -LiteralPath $backupDir) {
        Remove-Item -LiteralPath $backupDir -Recurse -Force
    }
    Write-Output 'Deployed commit __COMMIT__ to server5.'
} finally {
    if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
    if (Test-Path -LiteralPath $stagingDir) { Remove-Item -LiteralPath $stagingDir -Recurse -Force }
}
'@
$remoteScript = $remoteScript.Replace('__S3_URI__', $s3Uri).Replace('__AWS_REGION__', $AwsRegion).Replace('__COMMIT__', $commit)
$parametersPath = Join-Path ([System.IO.Path]::GetTempPath()) "ssm-parameters-$([Guid]::NewGuid().ToString('N')).json"
try {
    @{ commands = @($remoteScript); executionTimeout = @('900') } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $parametersPath -Encoding utf8
    $commandId = Invoke-Aws ssm send-command --instance-ids $instanceId `
        --document-name AWS-RunPowerShellScript `
        --parameters "file://$parametersPath" --timeout-seconds 600 `
        --comment "Deploy $commit to server5" `
        --query 'Command.CommandId' --output text
} finally {
    if (Test-Path -LiteralPath $parametersPath) { Remove-Item -LiteralPath $parametersPath -Force }
    if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
}
Write-Output "SSM command: $commandId; instance: $instanceId; commit: $commit"

$deadline = (Get-Date).AddMinutes(20)
do {
    $invocations = @(Invoke-Aws ssm list-command-invocations `
        --command-id $commandId --instance-id $instanceId `
        --query 'CommandInvocations' --output json | ConvertFrom-Json)
    $status = if ($invocations.Count -eq 0) { 'Pending' } else { $invocations[0].Status }
    if ($status -notin @('Pending', 'InProgress', 'Delayed')) { break }
    Start-Sleep -Seconds 10
} while ((Get-Date) -lt $deadline)

Invoke-Aws ssm get-command-invocation --command-id $commandId --instance-id $instanceId `
    --query '{Status:Status,ResponseCode:ResponseCode,Stdout:StandardOutputContent,Stderr:StandardErrorContent}' --output json
if ($status -ne 'Success') { throw "Deployment failed or timed out: $status" }