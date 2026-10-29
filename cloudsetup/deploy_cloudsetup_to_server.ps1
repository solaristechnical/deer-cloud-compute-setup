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
        'hostname',
        'whoami',
        'Write-Host Skipping first-time setup commands',
        #####
        # 1. Create a private ssh_deploy_key and save it to C:\ProgramData\ssh\ssh_deploy_key
        # (Note: Run this command interactively via SSM session instead of sendcommand.)
        # '& "C:\Program Files\Git\usr\bin\ssh-keygen.exe" -t ed25519 -b 4096 -f "C:\ProgramData\ssh\ssh_deploy_key" -N ""',

        #####
        # 2. Store secrets and authorize a deploy key
        # Now, copy and save the randomart and copy the thumbrint in a secure location
        # Treat these as secrets and do not commit them to any repository.
        # In Github, open the repository settings, then find "Deploy keys".
        # Paste the thumbprint into Github to authorize a deploy key.

        #####
        # 3. Add github.com to the known hosts file and configure Git's SSH profile (non-interactively)
        # The private key needs to be available only to the SYSTEM account (and ssm-user during testing).
        # Grant the built-in SYSTEM account full access to the folder and key
        #'icacls "C:\ProgramData\ssh" /grant "SYSTEM:(OI)(CI)F" /T',
        #'icacls "C:\ProgramData\ssh\ssh_deploy_key" /grant "SYSTEM:F"',
        # Grant access to the ssm-user local account during testing
        #'icacls "C:\ProgramData\ssh\ssh_deploy_key" /grant "ssm-user:F"',
        # Set the GIT_SSH_COMMAND environment variable for the machine scope
        #'[Environment]::SetEnvironmentVariable("GIT_SSH_COMMAND", "ssh -i C:/ProgramData/ssh/ssh_deploy_key -o UserKnownHostsFile=C:/ProgramData/ssh/ssh_known_hosts -o StrictHostKeyChecking=accept-new", "Machine")',

        #####
        # 4. Complete configuration for Git SSH (non-interactively)
        # Add github.com to the known hosts file
        #'& "C:\Program Files\Git\usr\bin\ssh-keyscan.exe" github.com >> "C:\ProgramData\ssh\ssh_known_hosts"',
        # Tell git to use the specified SSH command for connecting to GitHub so it finds the deploy key and and known hosts file that we configured.
        #'git config --system core.sshCommand "ssh -i C:/ProgramData/ssh/ssh_deploy_key -o UserKnownHostsFile=C:/ProgramData/ssh/ssh_known_hosts"'
        # Alternatively, put these parameters into a config file:
        #'[System.IO.File]::WriteAllText("C:\ProgramData\ssh\config", "Host github.com`n  IdentityFile C:/ProgramData/ssh/ssh_deploy_key`n  UserKnownHostsFile C:/ProgramData/ssh/ssh_known_hosts`n  StrictHostKeyChecking accept-new")',

        #####
        # Reboot after this, do not re-run the commands above
        
        'Write-Host Running your commands',
        'Write-Host environment variable GIT_SSH_COMMAND: $env:GIT_SSH_COMMAND',
        #'ssh -T git@github.com',
        '$RepoDir = "C:\DEER\deer-cloud-compute-setup"',
        'if (-not (Test-Path "$RepoDir\.git")) {git clone git@github.com:simularis/deer-cloud-compute-setup.git "$RepoDir"}',
        'git -C $RepoDir fetch origin',
        'git -C $RepoDir checkout main',
        'git -C $RepoDir reset --hard origin/main',
        'git -C $RepoDir clean -fd',
        '$WorkflowCommit = git -C $RepoDir rev-parse HEAD',
        'Write-Host "WorkflowCommit: $WorkflowCommit"',
        #'powershell "C:\DEER\deer-cloud-compute-setup\Install-All.ps1"',
        #'powershell ""C:\DEER\deer-cloud-compute-setup\Test-Environment.ps1"',
        'Write-Host Done now.'
        )
} | ConvertTo-Json -Compress

$ssm = (aws ssm send-command `
  --instance-ids $instanceId `
  --document-name AWS-RunPowerShellScript `
  --output json `
  --parameters $params `
  --cloud-watch-output-config CloudWatchOutputEnabled=true,CloudWatchLogGroupName="/aws/ssm/githubactions" `
  | ConvertFrom-Json)

$COMMAND_ID = $ssm.Command.CommandId

aws ssm wait command-executed `
    --command-id $COMMAND_ID `
    --instance-id $instanceId

aws ssm get-command-invocation `
  --command-id $ssm.Command.CommandId `
  --instance-id $ssm.Command.InstanceIds[0] `
  --query "{Stdout:StandardOutputContent,Stderr:StandardErrorContent}" `
  --output text

# aws ec2 stop-instances --instance-ids $instanceId