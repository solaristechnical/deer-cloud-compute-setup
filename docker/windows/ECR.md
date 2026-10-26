# Publish the Windows image to Amazon ECR

Use an **Amazon Elastic Container Registry (ECR) private repository** to store
`deer-windows:local`. Run these commands on the Windows Docker host, not inside
the container. This guide assumes the authenticated AWS identity and the ECR
repository are in the same AWS account, in the standard AWS commercial partition.

## Prerequisites and permissions

- AWS CLI v2 installed on the host with an authorized profile. Prefer IAM
  Identity Center/SSO or other temporary credentials, not long-lived access keys.
- Docker running in Windows-container mode and the tested `deer-windows:local`
  image available locally.
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

## 3. Authenticate Docker

```powershell
$EcrPassword = aws ecr get-login-password --profile $AwsProfile --region $Region
if ($LASTEXITCODE -ne 0) { throw 'Unable to get the ECR login token.' }
try {
    $EcrPassword | docker login --username AWS --password-stdin $Registry
    if ($LASTEXITCODE -ne 0) { throw 'Docker login to ECR failed.' }
}
finally {
    Remove-Variable EcrPassword
}
```

The token is valid for 12 hours. Repeat this step if authentication expires.
Never print the token, put it in source control, or pass it through Docker build
arguments. Docker stores login information using its configured credential
store; removing the PowerShell variable does not log Docker out.

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
If the connection fails, retry `docker push $RemoteImage`; reauthenticate first
if needed. If ECR reports `ImageTagAlreadyExistsException` for a changed image,
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
transfer test, repeat login, pull, and environment checks on another compatible
Windows Docker host with the pull permissions above. That host must also be able
to retrieve any Windows base layers referenced from Microsoft Container Registry.
Depending on the Windows image/daemon, these layers may be stored as external
("foreign" or nondistributable) layers rather than uploaded to ECR. A private ECR
repository alone therefore does not guarantee an offline/air-gapped deployment.
See AWS's [Windows image layer guidance](https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html).
Do not enable nondistributable-layer upload without reviewing Microsoft licensing
and the additional storage cost.

ECR login only authorizes image transfer. The simulation workflow still needs
separate runtime AWS credentials/IAM permissions, as described in the
[container guide](README.md#run); no credentials are baked into this image.

## 6. Log out when finished

```powershell
docker logout $Registry
if ($LASTEXITCODE -ne 0) { throw 'Docker logout failed.' }
```

This removes Docker's saved login for that registry, not the uploaded image.
Configure an ECR lifecycle policy with your administrator to control storage
costs, retaining the tagged/digest-pinned releases still needed by deployments.

Reference: [AWS instructions for pushing to private ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html).
