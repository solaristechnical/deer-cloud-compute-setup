# Publish the Windows image to Amazon ECR

Use an **Amazon Elastic Container Registry (ECR) private repository** to store
`deer-windows:local`. Run these commands on the Windows Docker host, not inside
the container. This guide assumes the authenticated AWS identity and the ECR
repository are in the same AWS account, in the standard AWS commercial partition.

To build and publish on AWS rather than a local host, use the
[GitHub Actions and Windows CodeBuild guide](aws/README.md).

## Prerequisites and permissions

- AWS CLI v2 installed on the host with an authorized profile. Prefer IAM
  Identity Center/SSO or other temporary credentials, not long-lived access keys.
- Docker running in Windows-container mode and the tested `deer-windows:local`
  image available locally.
- Amazon ECR Docker Credential Helper installed on the Windows host and
  configured for the target registry, as described below. It is not installed
  in the simulation image.
- Outbound HTTPS access from the host/Docker daemon to AWS ECR and its backing
  storage. A proxy, VPN, or firewall must permit the upload.
- Review vendor redistribution licenses before uploading the image. ECR is
  private, but uploading is still distribution/storage of the included software.
  Storage and data-transfer charges can apply; this Windows image is large.

An administrator should grant the publishing identity:

| Scope | IAM actions |
| --- | --- |
| `*` | `ecr:GetAuthorizationToken` |
| Target repository ARN | `ecr:DescribeRepositories`, `ecr:DescribeImages`, `ecr:BatchCheckLayerAvailability`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`, `ecr:PutImage`, `ecr:BatchGetImage`, `ecr:GetDownloadUrlForLayer` |
| Target repository ARN, only if creating it | `ecr:CreateRepository` |

The repository ARN has the form
`arn:aws:ecr:REGION:ACCOUNT_ID:repository/deer-windows`.
An administrator can create the repository once so normal publishers do not
need `ecr:CreateRepository`. Registry/repository policies, organization policies,
and permission boundaries can further restrict these operations.

Pull-only identities need `ecr:GetAuthorizationToken` on `*`, plus
`ecr:BatchCheckLayerAvailability`, `ecr:BatchGetImage`, and
`ecr:GetDownloadUrlForLayer` on the repository. The metadata verification below
also needs `ecr:DescribeImages`.

### Install the ECR credential helper on Windows

Docker login can fail with `error saving credentials ... The stub received bad
data` when its configured `desktop` or `wincred` helper cannot save the ECR
token. That message alone does not establish the underlying Windows API defect.
For local Windows publishing, use the
[Amazon ECR Docker Credential Helper](https://github.com/awslabs/amazon-ecr-credential-helper)
instead of storing ECR tokens through those helpers.

The following installs the official Windows x64 v0.12.0 binary into a user-owned
directory, verifies its published SHA256 checksum, and adds it to the current
session's PATH. For Windows ARM64 hosts, select the `windows-arm64` binary and
matching checksum from the
[official release](https://github.com/awslabs/amazon-ecr-credential-helper/releases/tag/v0.12.0).
The helper architecture must match the host, not the image.

```powershell
$ErrorActionPreference = 'Stop'
$HelperDirectory = Join-Path $env:LOCALAPPDATA 'Amazon\ECRCredentialHelper'
$HelperPath = Join-Path $HelperDirectory 'docker-credential-ecr-login.exe'
$HelperBaseUrl = 'https://amazon-ecr-credential-helper-releases.s3.us-east-2.amazonaws.com/0.12.0/windows-amd64'
$DownloadPath = Join-Path $env:TEMP ("ecr-helper-" + [guid]::NewGuid().ToString('N') + '.exe')
$ChecksumPath = "$DownloadPath.sha256"
New-Item -ItemType Directory -Path $HelperDirectory -Force | Out-Null
try {
    Invoke-WebRequest -UseBasicParsing -Uri "$HelperBaseUrl/docker-credential-ecr-login.exe" -OutFile $DownloadPath
    Invoke-WebRequest -UseBasicParsing -Uri "$HelperBaseUrl/docker-credential-ecr-login.exe.sha256" -OutFile $ChecksumPath
    $ExpectedHash = ((Get-Content -LiteralPath $ChecksumPath -Raw).Trim() -split '\s+')[0]
    if ($ExpectedHash -notmatch '^[0-9a-fA-F]{64}$') { throw 'Invalid helper checksum manifest.' }
    if ((Get-FileHash -LiteralPath $DownloadPath -Algorithm SHA256).Hash -ne $ExpectedHash) {
        throw 'ECR credential helper SHA256 mismatch.'
    }
    Move-Item -LiteralPath $DownloadPath -Destination $HelperPath -Force
}
finally {
    if (Test-Path -LiteralPath $DownloadPath) { Remove-Item -LiteralPath $DownloadPath -Force }
    if (Test-Path -LiteralPath $ChecksumPath) { Remove-Item -LiteralPath $ChecksumPath -Force }
}
$env:PATH = "$HelperDirectory;$env:PATH"
Get-Command docker-credential-ecr-login.exe -ErrorAction Stop
docker-credential-ecr-login.exe -v
if ($LASTEXITCODE -ne 0) { throw 'ECR credential helper executable check failed.' }
```

For future terminals, add the printed helper directory to your **user Path**
using Windows "Edit environment variables for your account", then open a new
terminal. Alternatively, repeat the `$env:PATH` assignment above in each
publishing session. Do not replace the existing PATH.
Registry-specific Docker configuration is covered in step 3 after determining
the account and region.

## 1. Set variables and verify the account

Run the sections in order in the **same PowerShell session**. Commands check
native exit codes explicitly, so they work in Windows PowerShell 5.1 and
PowerShell 7.

```powershell
$ErrorActionPreference = 'Stop'
$AwsProfile = 'default'          # Change to your authorized AWS profile
$Region = 'us-east-1'            # Change to the intended ECR region
$RepositoryName = 'deer-windows'
$LocalImage = 'deer-windows:local'
$ImageTag = 'windows2022-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')

# For an SSO profile, sign in first:
# aws sso login --profile $AwsProfile
# if ($LASTEXITCODE -ne 0) { throw 'AWS SSO login failed.' }

$identityJson = aws sts get-caller-identity --profile $AwsProfile --region $Region --output json --no-cli-pager
if ($LASTEXITCODE -ne 0) { throw 'Unable to determine the AWS identity.' }
$Identity = $identityJson | ConvertFrom-Json
$AccountId = $Identity.Account
if ($AccountId -notmatch '^\d{12}$') { throw 'Unexpected AWS account ID.' }
$Registry = "$AccountId.dkr.ecr.$Region.amazonaws.com"
$RepositoryUri = "$Registry/$RepositoryName"
$RemoteImage = "${RepositoryUri}:$ImageTag"

Write-Host "AWS identity: $($Identity.Arn)"
Write-Host "Upload target: $RemoteImage"
# Verify that this is the intended account and region before continuing.

$imageJson = docker image inspect $LocalImage --format '{{json .}}'
if ($LASTEXITCODE -ne 0) { throw "Local image not found: $LocalImage" }
$LocalMetadata = $imageJson | ConvertFrom-Json
if ($LocalMetadata.Os -ne 'windows' -or $LocalMetadata.Architecture -ne 'amd64') {
    throw 'Expected a Windows/amd64 image.'
}
```

The timestamped tag avoids overwriting a prior release. Keep its value or the
full image URI for subsequent pulls; do not rely on the local `:local` tag or an
implicit `:latest`.

## 2. Create the private repository once

For a **new repository**, run:

```powershell
aws ecr create-repository `
  --profile $AwsProfile --region $Region `
  --repository-name $RepositoryName `
  --image-tag-mutability IMMUTABLE `
  --encryption-configuration encryptionType=AES256 `
  --no-cli-pager
if ($LASTEXITCODE -ne 0) { throw 'ECR repository creation failed.' }
```

If the repository already exists, **skip creation** and inspect it instead:

```powershell
aws ecr describe-repositories `
  --profile $AwsProfile --region $Region `
  --repository-names $RepositoryName --no-cli-pager
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the ECR repository.' }
```

Do not treat all creation errors as "already exists": an error can also mean
missing permissions, expired credentials, or a network failure. For an existing
repository, check its encryption, tag-mutability, lifecycle, and access policies
with the administrator. An immutable tag cannot be replaced; choose a new
`$ImageTag` for each changed image.

## 3. Configure Docker to authenticate with the helper

If you previously used manual `docker login`, first remove the old ECR login
**before adding the helper mapping**:

```powershell
docker logout $Registry
if ($LASTEXITCODE -ne 0) { throw 'Unable to clear the previous ECR login; inspect Docker credential storage.' }
```

Skip that one-time cleanup if you have not saved a login for this registry.
If cleanup encounters a credential-store error, resolve it before proceeding;
do not delete the entire Docker configuration or credentials for other registries.

Back up and edit the current user's Docker configuration, normally
`$env:USERPROFILE\.docker\config.json`. If `$env:DOCKER_CONFIG` is set, edit
`config.json` in that directory instead. **Merge** a registry-specific entry
into the existing `credHelpers` object (create it if absent):

```json
{
  "credHelpers": {
    "123456789012.dkr.ecr.us-east-1.amazonaws.com": "ecr-login"
  }
}
```

Replace the example hostname with the exact `$Registry` value from step 1,
without `https://` or a repository path. This is an example of the entry to
merge, **not a replacement for your whole configuration**. Preserve existing
`auths`, `credsStore`, other `credHelpers` entries, `currentContext`, and all
other settings. The registry-specific `ecr-login` mapping takes precedence
over a global `credsStore` such as `desktop` or `wincred`; keep those helpers
for other registries. Do not change the global `credsStore` to `ecr-login`.

In the publishing PowerShell session, select the same AWS profile for the helper:

```powershell
$env:AWS_PROFILE = $AwsProfile
Get-Command docker-credential-ecr-login.exe -ErrorAction Stop
# Optional: avoid persisting ECR tokens in the helper's local file cache.
$env:AWS_ECR_DISABLE_CACHE = 'true'
```

AWS CLI `--profile` applies only to that CLI invocation; Docker's helper needs
`AWS_PROFILE` separately. Refresh an expired SSO session with
`aws sso login --profile $AwsProfile`. Existing AWS credential environment
variables can override profile credentials; use a clean credential environment
so the helper authenticates as the account verified in step 1.

**Do not run `aws ecr get-login-password | docker login` with this setup.**
Docker invokes the helper automatically for `push` and `pull`, and the helper
obtains ECR tokens using your AWS credentials. No manual login/logout is needed.
Do not print helper credential responses or put tokens in build arguments.

## 4. Tag and upload

```powershell
docker tag $LocalImage $RemoteImage
if ($LASTEXITCODE -ne 0) { throw 'Docker image tagging failed.' }

docker push $RemoteImage
if ($LASTEXITCODE -ne 0) { throw 'Docker image upload failed.' }

Write-Host "Published: $RemoteImage"
```

Tagging does not duplicate the local image layers. The first upload can take a
long time; subsequent uploads reuse layers already in this ECR repository.
If the connection fails, retry `docker push $RemoteImage`; refresh the AWS/SSO
session first if needed. If ECR reports `ImageTagAlreadyExistsException` for a changed image,
select a new tag and repeat tagging and pushing rather than disabling immutability.

## 5. Verify ECR metadata, pull by digest, and test

```powershell
$Digest = aws ecr describe-images `
  --profile $AwsProfile --region $Region `
  --repository-name $RepositoryName `
  --image-ids "imageTag=$ImageTag" `
  --query 'imageDetails[0].imageDigest' --output text --no-cli-pager
if ($LASTEXITCODE -ne 0) { throw 'Unable to verify the published image.' }
if ($Digest -notmatch '^sha256:[0-9a-f]{64}$') { throw 'Unexpected image digest.' }
$PinnedImage = "${RepositoryUri}@$Digest"
Write-Host "Digest-pinned image: $PinnedImage"

docker pull $PinnedImage
if ($LASTEXITCODE -ne 0) { throw 'Pull from ECR failed.' }
$pulledId = docker image inspect $PinnedImage --format '{{.Id}}'
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the pulled image.' }
if ($pulledId -ne $LocalMetadata.Id) { throw 'Pulled image differs from the local image.' }

docker run --rm --isolation=hyperv --network "Default Switch" `
  $PinnedImage pwsh -NoLogo -NoProfile -File C:\container\Test-Container.ps1
if ($LASTEXITCODE -ne 0) { throw 'Published image environment checks failed.' }
```

Use an available working network on your host; `Default Switch` is the network
verified on the development machine. On Windows Server 2022, process isolation
may be used instead. Save the digest-pinned URI for deployments so you run the
exact image verified here.

Pulling on the publishing host may reuse cached layers. For an independent
transfer test, repeat helper installation/configuration, pull, and environment checks on another compatible
Windows Docker host with the pull permissions above. That host must also be able
to retrieve any Windows base layers referenced from Microsoft Container Registry.
Depending on the Windows image/daemon, these layers may be stored as external
("foreign" or nondistributable) layers rather than uploaded to ECR. A private ECR
repository alone therefore does not guarantee an offline/air-gapped deployment.
See AWS's [Windows image layer guidance](https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html).
Do not enable nondistributable-layer upload without reviewing Microsoft licensing
and the additional storage cost.

The helper only supplies credentials for image transfer. The simulation workflow still needs
separate runtime AWS credentials/IAM permissions, as described in the
[container guide](README.md#run); no credentials are baked into this image.

## 6. Credential cleanup and troubleshooting

Do not run `docker logout` as a cleanup step with `ecr-login`: the helper does
not store credentials through Docker's `store`/`erase` interface. The configuration
entry can remain for future publishing. With `AWS_ECR_DISABLE_CACHE=true`, the
helper does not read or write its local ECR token cache. That setting does not
remove tokens cached by previous sessions.

By default, helper cache/log files are under `$env:USERPROFILE\.ecr` (or the
configured `AWS_ECR_CACHE_DIR`). Treat them as sensitive. Logs can help diagnose
profile or authorization failures; do not publish unredacted credential data.
For an SSO session, `aws sso logout --profile $AwsProfile` clears cached SSO
sessions across profiles and can affect other work; only do so when intended.
Neither removing local credentials nor logging out deletes the uploaded image.
Configure an ECR lifecycle policy with your administrator to control storage
costs, retaining the tagged/digest-pinned releases still needed by deployments.

References:
[ECR credential helper installation, configuration, and troubleshooting](https://github.com/awslabs/amazon-ecr-credential-helper),
[AWS instructions for pushing to private ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html).
