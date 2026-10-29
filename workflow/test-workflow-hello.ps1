# test-workflow-hello.ps1
# Requires PowerShell 7.3+ (pwsh); not compatible with Windows PowerShell 5.1.

$PSNativeCommandUseErrorActionPreference = $true
$ErrorActionPreference = 'Stop'

Write-Host "Importing Workflow module ..."
Import-Module .\workflow\Workflow.psm1 -Force
Get-Command Invoke-WorkflowStep
Get-Command Update-Manifest
Get-Command Invoke-DEERWorkflowController
Get-Command Invoke-GenerateManifest

Write-Host "Generating run-manifest ..."
$WorkingDirectory = "C:\temp\test"
$manifestPath = "$WorkingDirectory\run-manifest.json"
Invoke-GenerateManifest -manifestPath $manifestPath -RequestedSteps @("hello-world")

Write-Host "Invoke hello-world ..."
$result = Invoke-WorkflowStep `
    -StepName "hello-world" `
    -OutputDirectory "C:\temp\test" `
    -WorkingDirectory "C:\temp\test" `
    -Command {
        "hello world" |
            Set-Content "C:\temp\test\hello.txt"

        return [PSCustomObject]@{
            RunStatus = "Success"
            OutputFiles = [PSCustomObject]@(
                [PSCustomObject]@{
                    path  = "hello.txt"
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

Write-Host $result
if ($result.Status -eq "Success") {
    write-host "Succeeded"
    # python MeasureQc.py
}

Update-Manifest -WorkingDirectory "C:\temp\test"
