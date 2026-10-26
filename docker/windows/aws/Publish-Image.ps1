# Runs on the Windows Server 2022 CodeBuild host, not inside the target image.
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

foreach ($name in @('ECR_REPOSITORY_URI', 'ECR_REPOSITORY_NAME', 'IMAGE_TAG', 'SOURCE_COMMIT', 'AWS_DEFAULT_REGION')) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
        throw "Required CodeBuild environment variable is missing: $name"
    }
}
if ($env:IMAGE_TAG -notmatch '^sha-[0-9a-f]{40}-[0-9]+-[0-9]+$' -or $env:SOURCE_COMMIT -notmatch '^[0-9a-f]{40}$') {
    throw 'Invalid immutable image tag or source commit.'
}
if (-not $env:IMAGE_TAG.StartsWith("sha-$($env:SOURCE_COMMIT)-")) {
    throw 'Image tag does not match the source commit.'
}

function Assert-ExitCode {
    param([string]$Operation)
    if ($LASTEXITCODE -ne 0) {
        throw "$Operation failed with exit code $LASTEXITCODE"
    }
}

$dockerOs = docker info --format '{{.OSType}}'
Assert-ExitCode 'Docker readiness check'
if ($dockerOs -ne 'windows') {
    throw 'CodeBuild must provide a Windows Docker daemon.'
}

$env:IMAGE_URI = "$($env:ECR_REPOSITORY_URI):$($env:IMAGE_TAG)"
$registry = ($env:ECR_REPOSITORY_URI -split '/')[0]
$previousDockerConfig = $env:DOCKER_CONFIG
$dockerConfig = Join-Path $env:TEMP ("deer-ecr-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $dockerConfig | Out-Null
try {
    # Avoid desktop/wincred helpers; this disposable directory exists only for this build.
    [IO.File]::WriteAllText((Join-Path $dockerConfig 'config.json'), '{}', [Text.UTF8Encoding]::new($false))
    $env:DOCKER_CONFIG = $dockerConfig

    docker build --pull --isolation=process --file .\docker\windows\Dockerfile --tag $env:IMAGE_URI .
    Assert-ExitCode 'Windows image build'
    docker run --rm --isolation=process $env:IMAGE_URI pwsh -NoProfile -File C:\container\Test-Container.ps1
    Assert-ExitCode 'Container environment checks'

    $password = aws ecr get-login-password --region $env:AWS_DEFAULT_REGION
    Assert-ExitCode 'ECR token request'
    try {
        $password | docker login --username AWS --password-stdin $registry
        Assert-ExitCode 'ECR login'
    }
    finally {
        Remove-Variable password
    }
    docker push $env:IMAGE_URI
    Assert-ExitCode 'ECR push'

    $digest = aws ecr describe-images --region $env:AWS_DEFAULT_REGION `
        --repository-name $env:ECR_REPOSITORY_NAME --image-ids "imageTag=$($env:IMAGE_TAG)" `
        --query 'imageDetails[0].imageDigest' --output text --no-cli-pager
    Assert-ExitCode 'ECR digest verification'
    if ($digest -notmatch '^sha256:[0-9a-f]{64}$') {
        throw "ECR returned an invalid image digest: $digest"
    }
    $localId = docker image inspect $env:IMAGE_URI --format '{{.Id}}'
    Assert-ExitCode 'Local image inspection'
    $pinned = "$($env:ECR_REPOSITORY_URI)@$digest"
    docker pull $pinned
    Assert-ExitCode 'Digest-pinned ECR pull'
    $pulledId = docker image inspect $pinned --format '{{.Id}}'
    Assert-ExitCode 'Pulled image inspection'
    if ($pulledId -ne $localId) {
        throw 'The image pulled from ECR differs from the tested image.'
    }
    $env:IMAGE_DIGEST = $digest
    Write-Host "Published and verified: $pinned"
}
finally {
    $env:DOCKER_CONFIG = $previousDockerConfig
    Remove-Item -LiteralPath $dockerConfig -Recurse -Force
}
