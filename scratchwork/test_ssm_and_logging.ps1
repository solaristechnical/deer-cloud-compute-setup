# Requires PowerShell 7.3+ (pwsh); not compatible with Windows PowerShell 5.1.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

# Uncomment if aws CLI is not in the system PATH
#$awsExe = 'C:\Program Files\Amazon\AWSCLIV2\aws.exe'

#$instanceId = (aws ec2 describe-instances --filters "Name=tag:Name,Values=server5" --query "Reservations[*].Instances[*].InstanceId" --output text)
$instanceId = $env:SIMULATION_INSTANCE_ID
if (-not $instanceId) { throw 'Set SIMULATION_INSTANCE_ID in the local environment.' }

aws ec2 start-instances --instance-ids $instanceId
aws ec2 wait instance-running --instance-ids $instanceId
$status = (aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$instanceId" --query 'InstanceInformationList[0].PingStatus' --output text)
write-host $status

aws ssm describe-instance-information `
    --filters "Key=InstanceIds,Values=$instanceId" `
    --query "InstanceInformationList[0].PingStatus" `
    --output text

$params = @{
    commands = @(
      '$MachinePath = [Environment]::GetEnvironmentVariable(''Path'', ''Machine'')',
      '$UserPath = [Environment]::GetEnvironmentVariable(''Path'', ''User'')',
      '$env:Path = "$MachinePath;$UserPath"',
        'whoami',
        'hostname',
        'Get-Command aws',
        'aws --version',
        'where conda.exe',
        '$CondaExe = "C:\ProgramData\Anaconda3\Scripts\conda.exe"',
        '& $CondaExe --version',
        '& $CondaExe info --envs',
        '& $CondaExe env list',
        'Get-Content C:/DEER/deer-cloud-compute-setup/workflow/BootstrapSimulation.ps1 -First 5 | Format-Hex',
        'Get-Content C:/DEER/deer-cloud-compute-setup/workflow/BootstrapSimulation.ps1 -Head 20',
        'Get-Item C:\DEER\deer-cloud-compute-setup\workflow\BootstrapSimulation.ps1 | Select-Object FullName, LastWriteTime'
  )
} | ConvertTo-Json -Compress

# Other commands: copy/paste into commands.
<# (
        '& $CondaExe env list'

        'Get-ChildItem -Recurse C:\ -Filter conda.exe -ErrorAction SilentlyContinue',
        'aws logs describe-log-streams --log-group-name "/aws/ssm/githubactions"',
        'Set-Location C:\Scripts',
        '& $CondaExe run --no-capture-output -n py314 papermill test.ipynb test_out.ipynb'
        'Set-Location E:\githubactions\34809077068\qc',
        '& $CondaExe activate py314',
        'papermill "<QC_INPUT_NOTEBOOK>" "<QC_OUTPUT_NOTEBOOK>" -p simfolder "<SIMULATION_FOLDER>" -p output_file "<OUTPUT_FILE>" *> papermill.log'
        '& $CondaExe run --no-capture-output -n py314 python -c "from jupyter_client import KernelManager; km=KernelManager(); km.start_kernel(); print(''started'')"'
) #>

<#
$params = @{
  commands = @(
    'powershell C:/Scripts/BootstrapSimulation.ps1 `
    -RunId "<RUN_ID>" `
    -Repository "<REPOSITORY>" `
    -CommitSha "<COMMIT_SHA>" `
    -MeasurePath "<MEASURE_PATH>" `
    -S3Bucket "<SIMULATION_BUCKET>" `
    -RunAttempt "<RUN_ATTEMPT>"' `
  )
} | ConvertTo-Json -Compress
#>

# Use this version of the command to capture the output as a log stream in CloudWatch Logs. The output will be available in the log group "/aws/ssm/githubactions".
$ssm = (aws ssm send-command `
 --instance-ids $instanceId `
 --document-name AWS-RunPowerShellScript `
 --cloud-watch-output-config CloudWatchOutputEnabled=true,CloudWatchLogGroupName="/aws/ssm/githubactions" `
 --output json `
 --parameters $params `
 | ConvertFrom-Json)

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

# Example syntax for a session to pipe commands one at a time.
# This starts an interactive shell session. 
# If the Windows instance defaults to cmd, just type 'powershell' once connected.
# aws ssm start-session --target "$env:SIMULATION_INSTANCE_ID"
# Run a specific command
# aws ssm start-session \
#     --target "$env:SIMULATION_INSTANCE_ID" \
#     --document-name "AWS-StartInteractiveCommand" \
#     --parameters 'command=["powershell.exe -Command Get-Process"]'
