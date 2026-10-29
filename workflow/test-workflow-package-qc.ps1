# test-workflow-package-qc.ps1
# Requires PowerShell 7.3+ (pwsh); not compatible with Windows PowerShell 5.1.

param(
    [string]$RunId,
    [int]$RunAttempt,
    [string]$Repository,
    [string]$CommitSha,
    [string]$MeasurePath,
    [string]$S3Bucket,
    [System.Object]$RequestedSteps
)

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'
$PSStyle.OutputRendering = 'PlainText'
$InformationPreference = 'Continue'

Write-Host "RunId: $RunId"
Write-Host "CommitSha: $CommitSha"
Write-Host "MeasurePath: $MeasurePath"

Write-Host "Importing Workflow module ..."
Import-Module `
  "C:\DEER\deer-cloud-compute-setup\workflow\Workflow.psm1" `
  -Force
Get-Command Invoke-WorkflowStep
Get-Command Update-Manifest
Get-Command Invoke-DEERWorkflowController
Get-Command Invoke-GenerateManifest

Write-Host "Generating run-manifest ..."
$WorkingDirectory = "C:\githubactions\$RunId"
$manifestPath = "$WorkingDirectory\run-manifest.json"
Invoke-GenerateManifest `
    -manifestPath $manifestPath `
    -RunId $RunId `
    -RunAttempt $RunAttempt `
    -Repository $Repository `
    -CommitSha $CommitSha `
    -MeasurePath $MeasurePath `
    -RequestedSteps $RequestedSteps

Write-Host "Preparing to clone prototypes repository ..."
$Workspace = "C:\githubactions\$RunId"
$RepoDir = "$Workspace\repo"
Write-Host "Cloning repository into $RepoDir"
New-Item -ItemType Directory -Force -Path $Workspace

if (-not (Test-Path "$RepoDir\.git")) {
    Write-Host "Repository not found. Cloning..."
    git clone "https://github.com/$Repository.git" $RepoDir
}
else {
    Write-Host "Repository already exists. Reusing existing checkout."
}
git -C $RepoDir remote get-url origin

# In case the user re-runs the same job with a different commit, we need to fetch all commits to ensure the specified commit is available.
git -C $RepoDir fetch --all
git -C $RepoDir checkout $CommitSha

Write-Host "Invoke package-qc ..."
$result = Invoke-WorkflowStep `
    -RunId $RunId `
    -RunAttempt $RunAttempt `
    -S3Bucket $S3Bucket `
    -StepName "package-qc" `
    -OutputDirectory "$Workspace\outputs\package-qc" `
    -WorkingDirectory "$Workspace" `
    -Command {
        Write-Host "RepoDir=$RepoDir"
        Write-Host "MeasurePath=$MeasurePath"
        Write-Host "Output=$Workspace\outputs\package-qc"

        $CondaExe = "C:\ProgramData\Anaconda3\Scripts\conda.exe"

        & $CondaExe run `
            -n py314 `
            python `
            C:\DEER\deer-cloud-compute-setup\workflow\MeasureQc.py `
            "$RepoDir\$MeasurePath" `
            "$Workspace\outputs\package-qc"

        return [PSCustomObject]@{
            RunStatus = "Success"
            OutputFiles = [PSCustomObject]@(
                [PSCustomObject]@{
                    path  = "measure-qc.json"
                    bytes = 5123
                }
                [PSCustomObject]@{
                    path  = "scenario-index.json"
                    bytes = 5123
                }
                [PSCustomObject]@{
                    path  = "measure-qc.md"
                    bytes = 5123
                }
            )
            Metrics = [PSCustomObject]@{
                scenarioCount = 4
                measureBytes  = 12938432
                countClimates = 16
                countCohorts  = 128
            }
        }
    }

$result | ConvertTo-Json -Depth 10

Update-Manifest -WorkingDirectory "$WorkingDirectory"
