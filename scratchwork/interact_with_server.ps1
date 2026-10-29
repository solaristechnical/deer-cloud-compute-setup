# Requires PowerShell 7.3+ (pwsh); not compatible with Windows PowerShell 5.1.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

# Uncomment if aws CLI is not in the system PATH
#$awsExe = 'C:\Program Files\Amazon\AWSCLIV2\aws.exe'

#$instanceName = "server5"
$instanceName = "server5"
$instanceId = (aws ec2 describe-instances `
    --filters "Name=tag:Name,Values=$instanceName" `
    --query "Reservations[*].Instances[*].InstanceId" --output text)

# Make sure the instance is running and reachable via SSM before sending commands.
# This should print "online"
aws ec2 start-instances --instance-ids $instanceId
aws ec2 wait instance-running --instance-ids $instanceId
$status = (aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$instanceId" --query 'InstanceInformationList[0].PingStatus' --output text)
write-host $status

# Duplicate check:This should print "online"
aws ssm describe-instance-information `
    --filters "Key=InstanceIds,Values=$instanceId" `
    --query "InstanceInformationList[0].PingStatus" `
    --output text

# This starts an interactive shell session with the server, using the system account. 
# - If the Windows instance defaults to cmd, just type 'powershell' once connected.
# - Note that CloudWatch argument is used to capture the output as a log stream in CloudWatch Logs.
#   Logs will be streamed in CloudWatch / Logs / Log Management.
#   The output will be available in the log group "/aws/ssm/githubactions".

# Stream specific commands to a "session"
# aws ssm start-session `
#   --target "$instanceId" `
#   --document-name "AWS-StartInteractiveCommand" `
#   --parameters 'command=["powershell.exe -Command Get-Process"]'

# Just open the session and drop into an interactive shell.
aws ssm start-session `
  --target "$instanceId" `
  --document-name "AWS-StartInteractiveCommand" `
  --parameters 'command=["powershell.exe"]'

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

