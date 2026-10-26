# DEER Windows simulation container

This builds the simulation environment from `serversetup\Install-All.ps1` on
`mcr.microsoft.com/windows/servercore:ltsc2022` (Windows/amd64), without requiring
winget, a desktop, or interactive installer prompts. Existing server setup
scripts are unchanged.

## Included setup

| Component | Container setup |
| --- | --- |
| Windows configuration | Long paths enabled; PowerShell 7.4.13 |
| Git | Git for Windows 2.56.0.4; system `core.longpaths=true` |
| AWS CLI | AWS CLI v2 from the current signed AWS MSI |
| EnergyPlus | 9.5.0 in `C:\EnergyPlusV9-5-0`; 22.2.0 in `C:\EnergyPlusV22-2-0` |
| Modelkit | Caboodle 0.9.3+59d2aa1, including bundled Ruby, in `C:\Modelkit` |
| Anaconda | Anaconda3 2026.07-1 in `C:\ProgramData\Anaconda3` |
| Python | Conda environment `py314`, Python 3.14, and `serversetup\requirements.txt` |
| Workflow | Local `workflow` files in `C:\DEER\deer-cloud-compute-setup\workflow`; bootstrap entry at `C:\Scripts\BootstrapSimulation.ps1` |

EnergyPlus is extracted from the official ZIP distributions rather than running
the desktop installers (which can prompt or fail registering GUI components).
Neither EnergyPlus version is added to PATH; use its explicit executable path.
Modelkit uses an explicit container installation directory rather than its
desktop default.

The image copies this checkout's workflow instead of cloning the two repositories
in `InstallDeerBootstrapper.ps1`. It uses the local workflow's bootstrap script
and does not include a separate `C:\DEER\bootstrapper` model repository.
The workflow clones the requested model repository at runtime. This avoids
requiring GitHub credentials during image construction.

**SSM Agent is intentionally excluded.** Keep it on the EC2/container host if
needed. This image does not register as an SSM managed node, launch an EC2
instance, or change the existing GitHub Actions/SSM orchestration. To use that
orchestration, the host must invoke `docker run` instead of invoking the
bootstrap script directly.

## Prerequisites

- A Docker engine switched to **Windows containers**, not Linux containers.
- A host compatible with Windows Server Core LTSC 2022. Windows Server 2022
  supports process isolation; supported Windows desktop hosts can use Hyper-V
  isolation. See Microsoft's [version compatibility guidance](https://learn.microsoft.com/virtualization/windowscontainers/deploy-containers/version-compatibility).
- Network access to Microsoft Container Registry, GitHub release downloads,
  AWS, Big Ladder Software, Anaconda repositories, and PyPI.
- Sufficient disk space for the Windows base image, full Anaconda distribution,
  and both EnergyPlus installations. This is a large image, not a slim Python
  image.

Building silently installs the listed products and accepts the Anaconda channel
Terms of Service, matching `Install-Anaconda.ps1`. Review the applicable
[Anaconda terms and licensing](https://www.anaconda.com/legal) and other vendor
licenses before building or redistributing the image.

## Build

Run from the **repository root**, not this subfolder:

```powershell
docker info --format '{{.OSType}}' # Must report windows
docker build --isolation=hyperv -f .\docker\windows\Dockerfile -t deer-windows:local .
```

On Windows Server 2022, use `--isolation=process` if desired. The adjacent
`Dockerfile.dockerignore` allowlists only the build helpers, Python requirements,
and workflow source files; local credentials, `.git`, `.env`, scratchwork, and
working directories are not sent as build context.

Installers are downloaded, checked, run synchronously, and removed in their
installation layer. Fixed downloads use SHA256 checksums; the rolling AWS MSI
must have a valid Authenticode signature. Nonzero command/installer exit codes
fail the build (installer code 3010, success with reboot requested, is accepted).
Each tool has a separate cached layer. The base image tag and AWS CLI are rolling,
and Python/package dependencies follow the existing unpinned requirements, so
builds are not bit-for-bit reproducible. Use `--pull --no-cache` to refresh them.

The build runs `Test-Container.ps1` under PowerShell 7. It checks tool versions,
the `py314` environment, Python imports and dependency consistency, workflow
module loading, and long-path file creation. It does not perform a full
simulation or contact your AWS account.

The image explicitly includes the standard Windows system directories in PATH.
The checks also execute Windows PowerShell 5.1 and `chcp.com`, which helper
scripts can require even when their parent commands return exit code zero.
Messages such as `'powershell' is not recognized` or `'chcp' is not recognized`
are not expected; rebuild with the current Dockerfile if using an older image
with missing Windows PATH entries.

### Troubleshooting DNS during installation

The build needs outbound HTTPS and working DNS for installer downloads, Conda,
and pip. Docker supplies the build container's virtual network adapter; no
adapter configuration belongs in the Dockerfile.

If `Invoke-WebRequest` reports that `github.com` could not be resolved, test the
container network rather than just the host:

```powershell
docker network ls
docker run --rm --isolation=hyperv --network nat `
  mcr.microsoft.com/windows/servercore:ltsc2022 powershell -NoProfile -Command `
  "Resolve-DnsName github.com -ErrorAction Stop; (Invoke-WebRequest -UseBasicParsing -Uri https://github.com -Method Head -TimeoutSec 30).StatusCode"
```

On Docker Desktop hosts where the existing `Default Switch` network works but
`nat` has DNS timeouts, select that network explicitly:

```powershell
docker build --isolation=hyperv --network "Default Switch" -f .\docker\windows\Dockerfile -t deer-windows:local .
```

Use `--network "Default Switch"` with `docker run` as well if runtime AWS/Git
access needs it. This network is host-specific; use a working network from
`docker network ls` on other hosts. Build network selection does not persist in
the image.

Copying pre-downloaded installers into the image is possible but is not supported
by this Dockerfile. It would not make this build offline: Conda channels and pip
packages would also need local mirrors or pre-downloaded dependencies.

## Publish to AWS

See [Publish the Windows image to Amazon ECR](ECR.md) for host-side PowerShell
instructions to create a private repository, authenticate, push
`deer-windows:local`, and verify the uploaded image by digest. The guide includes
IAM permissions, Windows base-layer considerations, and credential cleanup.
For local Windows publishing, install and configure the Amazon ECR credential
helper as directed there; it bypasses Docker Desktop/Windows credential-storage
errors and authenticates ECR pushes and pulls without manual `docker login`.

## Run

Interactive PowerShell:

```powershell
docker run --rm -it --isolation=hyperv deer-windows:local
```

Repeat the environment checks:

```powershell
docker run --rm --isolation=hyperv deer-windows:local pwsh -NoProfile -File C:\container\Test-Container.ps1
```

Run the existing workflow with explicit inputs (replace the example values):

```powershell
New-Item -ItemType Directory -Path C:\DEER-container-runs -Force | Out-Null
docker run --rm --isolation=hyperv `
  --mount 'type=bind,source=C:\DEER-container-runs,target=C:\githubactions' `
  --mount "type=bind,source=$env:USERPROFILE\.aws,target=C:\Users\ContainerAdministrator\.aws,readonly" `
  -e AWS_PROFILE=default -e AWS_REGION=us-west-2 `
  deer-windows:local pwsh -NoProfile -File C:\Scripts\BootstrapSimulation.ps1 `
  -RunId 12345 -RunAttempt 1 `
  -Repository owner/model-repository -CommitSha REPLACE_WITH_COMMIT_SHA `
  -MeasurePath measures\example -S3Bucket your-bucket `
  -RequestedSteps package-qc
```

The host AWS configuration directory must exist. Supply credentials only at
runtime (for example the read-only mount above, including any required SSO cache,
or short-lived `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and
`AWS_SESSION_TOKEN` environment variables). Do not put credentials in build
arguments, the Dockerfile, or the image. Do not assume the host EC2 instance role
is automatically reachable from the container.

For multiple steps, invoke the bootstrap from a PowerShell `-Command` script
and pass a PowerShell array to `-RequestedSteps`, as with the server workflow.
The optional `-WorkflowPackageS3Key` still selects a workflow package from S3.
Private model repositories also require runtime Git authentication.

`C:\githubactions` is the workflow's existing work directory. Bind-mount it to
preserve files after `--rm`; S3 uploads still require the workflow's normal IAM
permissions. The image runs as `ContainerAdministrator`, as the server setup
expects, and starts no background agent. A noninteractive container exits when
its PowerShell command finishes.
