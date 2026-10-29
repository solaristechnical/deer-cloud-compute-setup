# Requires PowerShell 7.3+ (pwsh); not compatible with Windows PowerShell 5.1.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

# Uncomment if aws CLI is not in the system PATH
#$awsExe = 'C:\Program Files\Amazon\AWSCLIV2\aws.exe'

$instanceName = "server5"
$instanceId = (aws ec2 describe-instances `
    --filters "Name=tag:Name,Values=$instanceName" `
    --query "Reservations[*].Instances[*].InstanceId" --output text)

aws ec2 start-instances --instance-ids $instanceId
aws ec2 wait instance-running --instance-ids $instanceId
aws ec2 wait instance-status-ok --instance-ids $instanceId
$status = (aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$instanceId" --query 'InstanceInformationList[0].PingStatus' --output text)
write-host $status

aws ssm describe-instance-information `
    --filters "Key=InstanceIds,Values=$instanceId" `
    --query "InstanceInformationList[0].PingStatus" `
    --output text

$command = Get-Content -Path "$PSScriptRoot\..\serversetup\Test-Environment.ps1" -Raw

$params = @{
    commands = @($command)
} | ConvertTo-Json -Compress

# Use this version of the command to capture the output as a log stream in CloudWatch Logs. The output will be available in the log group "/aws/ssm/githubactions".
$ssm = (aws ssm send-command `
 --instance-ids $instanceId `
 --document-name AWS-RunPowerShellScript `
 --cloud-watch-output-config CloudWatchOutputEnabled=true,CloudWatchLogGroupName="/aws/ssm/githubactions" `
 --output json `
 --parameters $params `
 --comment "Running Test-Environment.ps1 on instance $instanceName" `
 | ConvertFrom-Json)

# $ssm = (aws ssm send-command `
#   --instance-ids $instanceId `
#   --document-name AWS-RunPowerShellScript `
#   --output json `
#   --parameters $params `
#   | ConvertFrom-Json)

$COMMAND_ID = $ssm.Command.CommandId
Write-Host "Command sent."
Write-Host "Command ID: $COMMAND_ID"
# wait 3 seconds
Start-Sleep -Seconds 3

$exitCode = 0
try {
    aws ssm wait command-executed `
        --command-id $COMMAND_ID `
        --instance-id $instanceId
} catch {
    $exitCode = $_.Exception.HResult
}
Write-Host "Command execution completed with exit code $exitCode."

try {
    aws ssm get-command-invocation `
      --command-id $ssm.Command.CommandId `
      --instance-id $ssm.Command.InstanceIds[0] `
      --query "{Stdout:StandardOutputContent,Stderr:StandardErrorContent}" `
      --output text
}
catch {
    write-host "Error waiting for command execution: $_"

    aws ssm get-command-invocation `
      --command-id $ssm.Command.CommandId `
      --instance-id $ssm.Command.InstanceIds[0]
}

## Optionally stop the instance after the interactive session.
$userInput = Read-Host "Do you want to stop the instance? (yes/no): "
if ($userInput -eq "yes") {
    aws ec2 stop-instances --instance-ids $instanceId
    aws ec2 wait instance-stopped --instance-ids $instanceId
    write-host "Instance $instanceId has been stopped."
}
else {
    write-host "Instance $instanceId will continue running."
    write-host "To stop the instance later: aws ec2 stop-instances --instance-ids $instanceId"
}
