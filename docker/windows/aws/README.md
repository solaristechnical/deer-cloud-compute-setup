# Build and publish on AWS from GitHub Actions

The manually dispatched workflow
[`publish-windows-container.yml`](../../../.github/workflows/publish-windows-container.yml)
uses **GitHub OIDC -> S3 source snapshot -> Windows Server 2022 CodeBuild ->
private ECR**. No local Docker host, permanent Windows runner, GitHub PAT, or
long-lived AWS key is required. The GitHub-hosted Ubuntu runner only submits
and monitors the cloud build; Windows Docker runs in AWS.

## One-time provisioning

Review [template.yml](template.yml) before deploying. It creates:

- An encrypted, private source bucket with HTTPS-only access and seven-day
  source expiration.
- A private ECR repository with immutable tags and AES256 encryption.
- A Windows Server 2022 CodeBuild project using
  `aws/codebuild/windows-base:2022-1.0`, on-demand `BUILD_GENERAL1_LARGE`
  compute, one concurrent build, a 180-minute build timeout, and a 30-minute
  queue timeout.
- A CloudWatch log group with 30-day retention.
- A CodeBuild role limited to source downloads, build logs, and this ECR
  repository (ECR authorization tokens necessarily use resource `*`).
- A separate GitHub OIDC role that can upload/delete sources and start, monitor,
  or stop builds for this project. Its trust policy permits only the specified
  GitHub repository's `main` branch.

Use an AWS region offering Windows Server 2022 CodeBuild and sufficient Windows
on-demand concurrency quota. Request a quota increase if provisioning reports
no available Windows capacity. The Windows large environment currently provides
16 GiB RAM, 8 vCPUs, and 128 GB disk; monitor disk utilization for this large
image and increase compute capacity if it becomes insufficient.

This project has no VPC configuration, so the managed build environment can
download from Microsoft Container Registry, GitHub, Big Ladder, AWS, Anaconda,
and PyPI. If you later attach it to a VPC, provide working DNS and outbound
internet/NAT access. `Default Switch` is a Docker Desktop network and is
**not** used on AWS. Windows does not support CodeBuild privileged mode; the
managed Windows environment supplies the Docker daemon, and this build uses
process isolation matching the LTSC 2022 base image.

An administrator must first create or identify the IAM OIDC provider for
`https://token.actions.githubusercontent.com` with audience `sts.amazonaws.com`.
Reuse the account's existing provider; do not create a duplicate. See
[GitHub's AWS OIDC setup](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws).

Using an administrator-authorized AWS CLI profile, run from the repository root
(replace the example account ID, profile, and owner/repository):

```powershell
$Region = 'us-east-1'
$Profile = 'admin'
$Stack = 'deer-windows-publisher'
$GitHubRepository = 'owner/deer-cloud-compute-setup'
$OidcProviderArn = 'arn:aws:iam::${AWS_ACCOUNT_NUMBER}:oidc-provider/token.actions.githubusercontent.com'

aws cloudformation deploy `
  --profile $Profile --region $Region `
  --stack-name $Stack `
  --template-file .\docker\windows\aws\template.yml `
  --capabilities CAPABILITY_IAM `
  --parameter-overrides `
    "GitHubRepository=$GitHubRepository" `
    "GitHubOidcProviderArn=$OidcProviderArn" `
    ProjectName=deer-windows-build `
    RepositoryName=deer-windows `
  --no-cli-pager
if ($LASTEXITCODE -ne 0) { throw 'Publisher stack deployment failed.' }

aws cloudformation describe-stacks `
  --profile $Profile --region $Region --stack-name $Stack `
  --query 'Stacks[0].Outputs' --output table --no-cli-pager
if ($LASTEXITCODE -ne 0) { throw 'Unable to read publisher stack outputs.' }
```

This creates billable resources. The stack owns a **new** ECR repository; if
`deer-windows` already exists from local publishing, choose a new
`RepositoryName` such as `deer-windows-ci` (or perform a separately reviewed
CloudFormation resource import). It does not silently adopt or replace an
existing repository. Project and log-group names must also be unused.
An administrator needs the CloudFormation, IAM, S3, ECR, CodeBuild, and Logs
permissions to provision these resources; the workflow itself cannot provision
or change infrastructure.

## GitHub configuration

Set repository **Settings -> Secrets and variables -> Actions -> Variables**:

| Repository variable | CloudFormation output |
| --- | --- |
| `AWS_REGION` | `AWSRegion` (defaults to `us-east-1` if unset) |
| `AWS_BUILD_ROLE_ARN` | `GitHubBuildRoleArn` |
| `WINDOWS_CODEBUILD_PROJECT` | `CodeBuildProjectName` |
| `WINDOWS_BUILD_SOURCE_BUCKET` | `SourceBucketName` |

No GitHub secret is required. The dedicated build role allows a four-hour OIDC
session so credentials remain valid during the long build and cleanup.
Do not substitute an unrelated deployment role without reviewing its trust,
permissions, and maximum session duration.

Commit/merge the workflow and build files to `main`. Run
**Actions -> Build and publish Windows container on AWS -> Run workflow**, with
`main` selected. Other branches are skipped and cannot assume the supplied
role. The selected main commit is archived from Git (not the runner's working
directory), with only `docker/windows`, `serversetup/requirements.txt`, and
`workflow` included. Untracked/local files and checkout credentials are not
uploaded. CodeBuild reads the snapshot from S3, so it requires no direct access
to a private GitHub repository.

Publishing is intentionally manual, not triggered by pull requests. Protect
`main` and review workflow, Dockerfile, buildspec, dependency, and installer
changes: anyone able to change trusted build code can run code with the build
role's ECR permissions. `codebuild:StartBuild` also permits build overrides, so
keep the GitHub submission role limited to trusted workflow code.
The build accepts the same vendor terms as the existing installer scripts;
review Anaconda/Microsoft/other redistribution terms before running it.

## Build, verification, and results

[buildspec.yml](buildspec.yml) invokes [Publish-Image.ps1](Publish-Image.ps1):

1. Check required environment variables, source/tag consistency, and Windows
   Docker readiness.
2. Build the existing Dockerfile with `--pull --isolation=process`. Its smoke
   tests must pass during image construction.
3. Launch a fresh container and rerun the environment checks before publishing.
4. Authenticate to ECR using the CodeBuild role's temporary credentials.
5. Push an immutable tag:
   `sha-<40-character-commit>-<GitHub-run-id>-<run-attempt>`.
6. Query ECR for its digest, pull by digest, and compare the pulled image ID
   with the tested local image.

Unlike a local Windows desktop, CodeBuild uses an isolated, temporary Docker
configuration with **no Windows credential-store helper**. It therefore does
not require installing `docker-credential-ecr-login`; manual ECR login here
does not use the problematic desktop/wincred API. The temporary Docker auth
file is deleted in `finally`. The build role is not passed into the simulation
container, and no credentials are baked into image layers.

The workflow polls CodeBuild status and reports the build ID, source commit,
image tag, digest-pinned URI, and CloudWatch log link in its run summary. Build
output is in CloudWatch, not streamed into the GitHub job log. AWS console log
access requires your own authorized identity. A non-success CodeBuild status,
missing publication output, failed test, or digest mismatch fails the job.

Normal completion/cancellation attempts to stop any unfinished build and delete
the uploaded source ZIP. Hard runner termination, expired credentials, or a
cancellation during submission can prevent cleanup. CodeBuild's own timeout
bounds orphaned builds; check CodeBuild for queued/running builds if needed and
stop them manually. The S3 lifecycle expires leftover source ZIPs.
The GitHub job allows four hours, including queue time, polling, and cleanup.

Rerunning the GitHub job produces a new tag through the attempt number.
If a push succeeds but subsequent verification fails, the image can remain in
ECR; inspect the logs before using it. No `latest` tag is overwritten.
The build does not run a full DEER simulation, deploy to ECS/EC2, or change the
existing simulation orchestration. Runtime AWS credentials remain separate.
The pull may reuse cached layers; test from a separate Windows host when
independent transfer verification is required.

The Windows base tag, AWS CLI, Python environment, and packages include rolling
dependencies. A source commit tag identifies the build source, not a
bit-for-bit reproducible image. Use the exported digest for deployments.
Windows foreign/base-layer and offline deployment considerations from the
[ECR guide](../ECR.md) still apply.

## Costs and removal

CodeBuild compute is on-demand, but S3/ECR storage and CloudWatch logs remain.
No CodeBuild local Docker cache or reserved fleet is configured; new builds
may redownload/install the full toolchain. Review costs before frequent builds.
Add a reviewed ECR lifecycle policy when you know which releases must be kept.

Deleting the stack retains the ECR repository/images and source bucket to
avoid accidental data loss. Delete those retained resources separately only
when no longer needed. Logs, the project, and IAM roles follow normal stack
deletion. No automatic AWS deployment is performed by adding these files.

AWS references:
[Windows CodeBuild images](https://docs.aws.amazon.com/codebuild/latest/userguide/ec2-compute-images.html),
[compute types and regional availability](https://docs.aws.amazon.com/codebuild/latest/userguide/build-env-ref-compute-types.html),
[Docker builds and Windows privilege limitations](https://docs.aws.amazon.com/codebuild/latest/userguide/sample-docker-custom-image.html).
