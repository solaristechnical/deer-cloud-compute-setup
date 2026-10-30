$ErrorActionPreference = 'Stop'

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "deer-simulate-test-$([guid]::NewGuid().ToString('N'))"
$module = Import-Module (Join-Path $PSScriptRoot 'Workflow.psm1') -Force -PassThru

try {
    & $module {
        param($testRoot)

        $script:testRepo = Join-Path $testRoot 'repo'
        $script:testScenarios = @("Scenario One's models", 'Scenario Two with spaces')
        $script:awsCalls = [System.Collections.Generic.List[object]]::new()
        $script:simulationRoots = [System.Collections.Generic.List[string]]::new()
        $measurePath = 'residential measures/Test measure'
        $measureRoot = Join-Path $script:testRepo $measurePath
        New-Item -ItemType Directory -Force -Path $measureRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $measureRoot '.modelkit-config') -Value 'max-workers = 1'
        foreach ($scenario in $script:testScenarios) {
            $runs = Join-Path (Join-Path $measureRoot $scenario) 'runs'
            New-Item -ItemType Directory -Force -Path $runs | Out-Null
            Set-Content -LiteralPath (Join-Path $runs 'instance.idf') -Value 'mock model'
        }

        function Initialize-DEERRepository { return $script:testRepo }
        function aws {
            $script:awsCalls.Add(@($args))
            if ($args[0] -eq 's3' -and $args[1] -eq 'cp' -and $args[2] -like '*/outputs/package-qc/scenario-index.json') {
                $script:testScenarios | ForEach-Object { @{ scenarioId = $_ } } |
                    ConvertTo-Json -AsArray | Set-Content -LiteralPath $args[3]
            }
        }
        function modelkit { }
        function Start-Job {
            param($ArgumentList, $ScriptBlock)
            $script:simulationRoots.Add($ArgumentList[0])
            Set-Content -LiteralPath $ArgumentList[1] -Value 'mock simulation completed'
            return [PSCustomObject]@{
                State = 'Completed'
                ChildJobs = @([PSCustomObject]@{ ExitCode = 0 })
            }
        }
        function Receive-Job { param($Job, [switch]$Keep, $ErrorAction) }
        function Stop-Job { param($Job, $ErrorAction) }
        function Remove-Job { param($Job, $ErrorAction) }

        for ($scenarioNumber = 1; $scenarioNumber -le 2; $scenarioNumber++) {
            $step = "simulate-$scenarioNumber"
            $scenario = $script:testScenarios[$scenarioNumber - 1]
            $workspace = Join-Path $testRoot $step
            Invoke-DEERWorkflowController -WorkingDirectory $workspace -RunId 'test-run' -RunAttempt 1 `
                -Repository 'example/models' -CommitSha 'test-sha' -MeasurePath $measurePath `
                -S3Bucket 'test-bucket' -RequestedSteps $step -ScenarioId $scenario `
                -WorkflowPackageS3Key 'githubactions/test-run/workflow.zip' | Out-Null

            $status = Get-Content -LiteralPath "$workspace/steps/$step/step-status.json" -Raw | ConvertFrom-Json
            if ($status.Status -ne 'Success' -or $status.Step -ne $step -or
                $status.Metrics.ScenarioId -cne $scenario -or $status.Metrics.ScenarioCount -ne 1) {
                throw "Unexpected status for ${step}: $($status | ConvertTo-Json -Depth 10)"
            }
            $manifest = Get-Content -LiteralPath "$workspace/run-manifest.json" -Raw | ConvertFrom-Json
            if ($manifest.steps.$step.Status -ne 'Success') { throw "Missing manifest status for $step" }
            if ($script:simulationRoots.Count -ne $scenarioNumber -or
                $script:simulationRoots[-1] -cne (Join-Path $measureRoot $scenario)) {
                throw "$step did not run exactly the selected scenario."
            }
            foreach ($suffix in @("steps/$step/step-status.json", "steps/$step/run-manifest.json",
                "steps/$step/summary.md", "outputs/$step", "attempt-1/transcript_$step.log")) {
                $expected = "s3://test-bucket/githubactions/test-run/$suffix"
                if (-not ($script:awsCalls | Where-Object { $_ -contains $expected })) {
                    throw "Missing isolated S3 upload: $expected"
                }
            }
            Write-Host "PASS: $step runs only '$scenario' with isolated artifacts"
        }

        if ($script:awsCalls | Where-Object { $_ -contains 's3://test-bucket/githubactions/test-run/run-manifest.json' -or
            $_ -contains 's3://test-bucket/githubactions/test-run/summary.md' }) {
            throw 'Parallel simulation overwrote shared workflow metadata.'
        }

        foreach ($invalidScenario in @('Not in index', '..', '../Scenario Two with spaces')) {
            $rejected = $false
            try {
                Invoke-DEERSimulate -RepoDir $script:testRepo -MeasurePath $measurePath `
                    -WorkingDirectory (Join-Path $testRoot 'invalid') -OutputDirectory (Join-Path $testRoot 'invalid/outputs') `
                    -S3RunPath 's3://test-bucket/githubactions/test-run' -ScenarioId $invalidScenario | Out-Null
            }
            catch {
                if ($_.Exception.Message -notlike 'ScenarioId must identify exactly one*') { throw }
                $rejected = $true
            }
            if (-not $rejected) { throw "Invalid scenario was accepted: $invalidScenario" }
            Write-Host "PASS: rejects '$invalidScenario'"
        }
        if ($script:simulationRoots.Count -ne 2) { throw 'Invalid scenario started a simulation.' }
    } $testRoot
}
finally {
    Remove-Module $module
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}