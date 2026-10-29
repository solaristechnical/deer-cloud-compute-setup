# Requires PowerShell 7.3+ (pwsh); not compatible with Windows PowerShell 5.1.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$instanceId = (aws ec2 describe-instances --filters "Name=tag:Name,Values=server5" --query "Reservations[*].Instances[*].InstanceId" --output text)

aws ec2 start-instances --instance-ids $instanceId
aws ec2 wait instance-running --instance-ids $instanceId

$status = (aws ssm describe-instance-information `
    --filters "Key=InstanceIds,Values=$instanceId" `
    --query "InstanceInformationList[0].PingStatus" `
    --output text)
write-host $status

$params = @{
    commands = @(
        'aws --version'
        )
} | ConvertTo-Json -Compress

$sae = (aws start-automation-execution `
  --document-name AWS-RunPowerShellScript `
    --parameters "AutomationAssumeRole=$env:AWS_SIMULATION_ROLE_ARN" `
  --output json
  )
$executionId = $sae.ExecutionId

aws ssm describe-automation-executions `
    --filter "Key=ExecutionId,Values=$executionId"

# $ssm = (aws ssm send-command `
#   --instance-ids $instanceId `
#   --document-name AWS-RunPowerShellScript `
#   --output json `
#   --parameters $params `
#   | ConvertFrom-Json)

$COMMAND_ID = $ssm.Command.CommandId

aws ssm wait command-executed `
    --command-id $COMMAND_ID `
    --instance-id $instanceId

aws ssm get-command-invocation `
  --command-id $ssm.Command.CommandId `
  --instance-id $ssm.Command.InstanceIds[0] `
  --query "{Stdout:StandardOutputContent,Stderr:StandardErrorContent}" `
  --output text
