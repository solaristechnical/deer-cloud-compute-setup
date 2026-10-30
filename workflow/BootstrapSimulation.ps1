# BootstrapSimulation.ps1
# Requires PowerShell 7.3+ (pwsh); not compatible with Windows PowerShell 5.1.
# Install to C:\DEER\BootstrapSimulation.ps1

param(
    [string]$RunId,
    [int]$RunAttempt,
    [string]$Repository,
    [string]$CommitSha,
    [string]$MeasurePath,
    [string]$S3Bucket,
    [System.Object]$RequestedSteps,
    [string]$ScenarioId,
    # S3 key (in $S3Bucket) of the deer-cloud-compute-setup ZIP archive frozen for this run.
    [string]$WorkflowPackageS3Key
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$PSStyle.OutputRendering = 'PlainText'
$InformationPreference = 'Continue'

# Use for persistent server with a data drive, E: 
#$Workspace = "E:\githubactions\$RunId"

# Use for ephemeral server
$Workspace = "C:\githubactions\$RunId"

New-Item -ItemType Directory -Force -Path $Workspace

$WorkflowCommitSha = $null
if ($WorkflowPackageS3Key) {
    if ($S3Bucket -notmatch '^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$') {
        throw 'S3Bucket must be an S3 bucket name.'
    }
    if ($WorkflowPackageS3Key -notmatch '^githubactions/[A-Za-z0-9._/-]+\.zip$' -or $WorkflowPackageS3Key -match '\.\.') {
        throw "Invalid WorkflowPackageS3Key: $WorkflowPackageS3Key"
    }

    $PackageDir = Join-Path $Workspace 'deer-cloud-compute-setup'
    $deployId = [Guid]::NewGuid().ToString('N')
    $archive = Join-Path $env:TEMP "workflow-package-$deployId.zip"
    $stagingDir = "$PackageDir-staging-$deployId"
    try {
        Write-Host "Downloading workflow package s3://$S3Bucket/$WorkflowPackageS3Key ..."
        & aws s3 cp "s3://$S3Bucket/$WorkflowPackageS3Key" $archive --only-show-errors
        if ($LASTEXITCODE -ne 0) { throw 'Failed to download workflow package.' }
        Expand-Archive -LiteralPath $archive -DestinationPath $stagingDir -Force
        if (-not (Test-Path -LiteralPath (Join-Path $stagingDir 'workflow\Workflow.psm1'))) {
            throw 'Workflow package does not contain the expected repository files.'
        }
        if (Test-Path -LiteralPath $PackageDir) {
            Remove-Item -LiteralPath $PackageDir -Recurse -Force
        }
        Move-Item -LiteralPath $stagingDir -Destination $PackageDir
    }
    finally {
        if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
        if (Test-Path -LiteralPath $stagingDir) { Remove-Item -LiteralPath $stagingDir -Recurse -Force }
    }

    $versionFile = Join-Path $PackageDir 'WORKFLOW_COMMIT'
    if (Test-Path -LiteralPath $versionFile) {
        $WorkflowCommitSha = (Get-Content -LiteralPath $versionFile -Raw).Trim()
    }
    Write-Host "Using workflow package commit: $WorkflowCommitSha"
}
else {
    Write-Warning 'No WorkflowPackageS3Key provided; using the installed deer-cloud-compute-setup.'
    $PackageDir = 'C:\DEER\deer-cloud-compute-setup'
}

Get-ChildItem (Join-Path $PackageDir 'workflow')

Write-Host "Importing Workflow module ..."
Import-Module (Join-Path $PackageDir 'workflow\Workflow.psm1') -Force

# Execute the workflow control function with the provided parameters
Invoke-DEERWorkflowController `
  -RunId $RunId `
  -Repository $Repository `
  -CommitSha $CommitSha `
  -MeasurePath "$MeasurePath" `
  -S3Bucket $S3Bucket `
  -RunAttempt $RunAttempt `
  -RequestedSteps $RequestedSteps `
    -ScenarioId $ScenarioId `
  -WorkflowPackageS3Key $WorkflowPackageS3Key `
  -WorkflowCommitSha $WorkflowCommitSha

# pwsh "C:\DEER\deer-cloud-compute-setup\workflow\test-workflow-package-qc.ps1" `
#   -RunId $RunId `
#   -Repository $Repository `
#   -CommitSha $CommitSha `
#   -MeasurePath "$MeasurePath" `
#   -S3Bucket $S3Bucket `
#   -RunAttempt $RunAttempt `
#   -RequestedSteps $RequestedSteps
