# DEER simulation workflow setup reference

This document lists the software requirements and the GitHub Actions variables and secrets used by
[run_deer_simulations.yml](../.github/workflows/run_deer_simulations.yml) and
[deploy-server5.yml](../.github/workflows/deploy-server5.yml).

## Software requirements

### GitHub-hosted runner (`ubuntu-latest`, `ubuntu-slim`)

The hosted images already include these tools. Self-hosted runners must provide them.

| Tool | Minimum version | Used for |
| --- | --- | --- |
| Git | 2.40 | `git archive --add-virtual-file` adds `WORKFLOW_COMMIT` to the workflow package ZIP |
| AWS CLI | v2 | EC2, SSM, and S3 calls |
| jq | 1.6 | Building SSM parameters and reading JSON status files |
| bash | 4 | Workflow `run` steps |

Check versions with:

```bash
git --version
aws --version
jq --version
```

### EC2 simulation servers (Windows AMI and server5)

| Software | Notes | Installer |
| --- | --- | --- |
| PowerShell 7.3+ (`pwsh`) | Required for `$PSNativeCommandUseErrorActionPreference` and `$PSStyle` | ConfigureWindows.ps1 |
| AWS CLI v2 | Downloads the workflow package and syncs artifacts to S3 | [Install-AwsCli.ps1](../serversetup/Install-AwsCli.ps1) |
| SSM Agent | Receives `AWS-RunPowerShellScript` commands | [Install-SSMAgent.ps1](../serversetup/Install-SSMAgent.ps1) |
| Git | Clones the measure (model) repository | [Install-Git.ps1](../serversetup/Install-Git.ps1) |
| Anaconda with `py314` env | Runs `MeasureQc.py` and `ComposeQc.py` ([requirements.txt](../serversetup/requirements.txt)) | [Install-Anaconda.ps1](../serversetup/Install-Anaconda.ps1) |
| Modelkit | `modelkit rake compose` | [InstallModelkit.ps1](../serversetup/InstallModelkit.ps1) |
| EnergyPlus | Simulation | [InstallEnergyPlus.ps1](../serversetup/InstallEnergyPlus.ps1) |
| Bootstrap script | `C:\DEER\deer-cloud-compute-setup\workflow\BootstrapSimulation.ps1` must be a version that accepts `-WorkflowPackageS3Key` | [deploy-server5.ps1](deploy-server5.ps1), then rebuild the AMI ([update-deer-ami.md](update-deer-ami.md)) |

The EC2 instance profile (`EC2InstanceRole`) needs `s3:GetObject` and `s3:PutObject` on
`arn:aws:s3:::<SIMULATION_BUCKET>/githubactions/*`.

### Local deployment workstation

To run [deploy-server5.ps1](deploy-server5.ps1) yourself, you need PowerShell 7, Git, and AWS CLI v2 with credentials that can use the deployment bucket, EC2, and Systems Manager.

## How the workflow package is frozen

1. On the first attempt of a run, `start-cloud` checks out `WORKFLOW_REPOSITORY` at `WORKFLOW_REF`. It zips the commit and uploads the ZIP to
   `s3://<SIMULATION_BUCKET>/githubactions/<run_id>/workflow-package/deer-cloud-compute-setup-<sha>.zip`.
2. It then writes `s3://<SIMULATION_BUCKET>/githubactions/<run_id>/workflow-package.json`, which records the commit SHA, the S3 key, and the S3 version ID.
3. Re-run attempts find `workflow-package.json` and reuse the recorded package, so later changes to `WORKFLOW_REF` do not affect an existing run.
4. Each server step receives `-WorkflowPackageS3Key`. The server extracts the package to
   `C:\githubactions\<run_id>\deer-cloud-compute-setup` and saves the key in `run-manifest.json`.

To force a new package version, start a new workflow run. Re-running an existing run keeps its package.

## Shared EC2 step action

The `package-qc`, `compose`, `compose-qc`, and `simulate` jobs in
[deer_simulations.yml](../.github/workflows/deer_simulations.yml) use the
[run-deer-ec2 composite action](../.github/actions/run-deer-ec2/action.yml). Each job checks out
`WORKFLOW_REPOSITORY` at the frozen `workflow_commit_sha` into `workflow_repo` before invoking the
local action. This also works when the reusable workflow is called from a model repository; a
default checkout would retrieve the caller's repository instead.

The action requires AWS credentials to be configured first. It accepts `instance-id`, `model-repo`,
`commit-sha`, `measure-path`, `s3-bucket`, `requested-step`, and `workflow-package-s3-key`. The run ID
and attempt come from the runner's `GITHUB_RUN_ID` and `GITHUB_RUN_ATTEMPT`.

It submits the bootstrap command through SSM, polls the invocation, downloads
`githubactions/<run_id>/steps/<requested-step>/step-status.json` to the job workspace, and fails
unless both SSM and DEER report `Success`. Status retrieval and validation still run after an SSM
failure so diagnostics remain available. Invalid or missing status files are retried ten times
with five-second delays, then reported as failures.

| Job | `poll-attempts` | `poll-interval-seconds` | Approximate polling window |
| --- | --- | --- | --- |
| `package-qc` | 120 (default) | 15 (default) | 30 minutes |
| `compose`, `compose-qc` | 120 (default) | 30 | 1 hour |
| `simulate` | 240 | 60 | 4 hours, within the existing job timeout |

These are bounded query counts, not extensions to AWS credential lifetimes or the job timeout.
Terminal SSM statuses, including `TimedOut`, stop polling and fail validation rather than waiting
indefinitely.

The action exposes `command_id`, `send_command_outcome`, `ssm_status`, `ssm_status_details`,
`ssm_response_code`, `step_status_available`, and `step_status` outputs, including on failure.
Artifact downloads, uploads, job-specific summaries, and instance cleanup remain in the workflow.
Package-QC artifact collection and its summary use `always()` so they still run when validation fails.

When deploying this refactor, set `WORKFLOW_REF` to a commit containing the action and start a new
workflow run. A previously frozen package from before the action was added cannot supply the new
local action.

To test the action locally without AWS access, install `jq` and
[mikefarah/yq v4](https://github.com/mikefarah/yq), then run from the repository root:

```bash
bash .github/actions/run-deer-ec2/test.sh
```

The tests execute the action's actual Bash scripts with mocked `aws` and `sleep` functions,
covering all four DEER steps, transient invocation errors, terminal SSM failures, polling limits,
status-file retries and validation, submission failures, and PowerShell argument quoting.

## Variables and secrets

Configure these in the repository that hosts `run_deer_simulations.yml`, under
**Settings > Secrets and variables > Actions**. Use the **Variables** tab for variables and the **Secrets** tab for secrets.

### Variables for `run_deer_simulations.yml`

| Name | Required | Example | Description |
| --- | --- | --- | --- |
| `AWS_SIMULATION_ROLE_ARN` | Yes | `${AWS_SIMULATION_ROLE_ARN}` | IAM role assumed through GitHub OIDC |
| `SIMULATION_BUCKET` | Yes | `${SIMULATION_BUCKET}` | S3 bucket name only, without the `s3://` prefix |
| `SIMULATION_INSTANCE_ID` | Yes | `${SIMULATION_INSTANCE_ID}` | Persistent instance (server5) used for package-qc, compose, and compose-qc |
| `WORKFLOW_REPOSITORY` | Yes | `solaristechnical/deer-cloud-compute-setup` | `owner/name` of this repository, which is bundled as the workflow package |
| `WORKFLOW_REF` | No | `main` | Branch, tag, or SHA to bundle. Defaults to `main` |
| `EC2_LAUNCH_TEMPLATE_ID` | Yes | `${EC2_LAUNCH_TEMPLATE_ID}` | Launch template for ephemeral simulation instances |
| `EC2_LAUNCH_TEMPLATE_VERSION` | Yes | `8` | Launch template version that uses the current AMI |
| `EC2_INSTANCE_TYPE_TEST` | Yes | `c8in.xlarge` | Instance type for the `test` run profile |
| `EC2_INSTANCE_TYPE_STANDARD` | Yes | `c8in.8xlarge` | Instance type for the `standard` run profile |
| `EC2_INSTANCE_TYPE_LARGE` | Yes | `c8in.32xlarge` | Instance type for the `large` run profile |

### Secrets for `run_deer_simulations.yml`

| Name | Required | Description |
| --- | --- | --- |
| `WORKFLOW_REPOSITORY_TOKEN` | Only if `WORKFLOW_REPOSITORY` is private and different from the calling repository | Fine-grained personal access token or GitHub App token with **Contents: Read-only** on `WORKFLOW_REPOSITORY`. The default `GITHUB_TOKEN` cannot read other private repositories. |

The reusable workflow declares `WORKFLOW_REPOSITORY_TOKEN` as optional. Caller workflows
must forward it on the job that calls the reusable workflow (the provided callers already do):

```yaml
secrets:
  WORKFLOW_REPOSITORY_TOKEN: ${{ secrets.WORKFLOW_REPOSITORY_TOKEN }}
```

All workflow-repository checkouts use this secret when set, falling back to `github.token`
when it is absent. The model-repository checkout continues to use the default `github.token`.

### Variables for `deploy-server5.yml` (optional)

| Name | Default | Description |
| --- | --- | --- |
| `AWS_REGION` | `us-east-1` | AWS region |
| `DEPLOY_BUCKET` | `${DEPLOY_BUCKET}` | Bucket used to stage the deployment ZIP |
| `AWS_DEPLOY_ROLE_ARN` | `GitHubSimulationRole` ARN | IAM role assumed for the deployment |

### Setting values with the GitHub CLI

```bash
REPO=solaristechnical/deer-cloud-compute-setup

gh variable set AWS_SIMULATION_ROLE_ARN --repo "$REPO" --body "$AWS_SIMULATION_ROLE_ARN"
gh variable set SIMULATION_BUCKET       --repo "$REPO" --body "$SIMULATION_BUCKET"
gh variable set SIMULATION_INSTANCE_ID  --repo "$REPO" --body "$SIMULATION_INSTANCE_ID"
gh variable set WORKFLOW_REPOSITORY     --repo "$REPO" --body "solaristechnical/deer-cloud-compute-setup"
gh variable set WORKFLOW_REF            --repo "$REPO" --body "main"
gh variable set EC2_LAUNCH_TEMPLATE_ID      --repo "$REPO" --body "$EC2_LAUNCH_TEMPLATE_ID"
gh variable set EC2_LAUNCH_TEMPLATE_VERSION --repo "$REPO" --body "7"
gh variable set EC2_INSTANCE_TYPE_TEST      --repo "$REPO" --body "c8in.xlarge"
gh variable set EC2_INSTANCE_TYPE_STANDARD  --repo "$REPO" --body "c8in.8xlarge"
gh variable set EC2_INSTANCE_TYPE_LARGE     --repo "$REPO" --body "c8in.32xlarge"

# Prompts for the value so the token is not stored in shell history.
gh secret set WORKFLOW_REPOSITORY_TOKEN --repo "$REPO"
```

## AWS permissions checklist

- **GitHub OIDC role (`GitHubSimulationRole`)**: needs `s3:GetObject` and `s3:PutObject` on
  `arn:aws:s3:::<SIMULATION_BUCKET>/githubactions/*` and `s3:ListBucket` on the bucket. See
  [custom-policy-GitHubSimulationRolePolicy.json](custom-policy-GitHubSimulationRolePolicy.json).
  - With `s3:ListBucket`, a missing `workflow-package.json` returns 404. Without it, S3 returns 403 instead.
  - The freeze check treats any failure to read `workflow-package.json` as "not frozen". Keep this permission so access problems are easier to diagnose.
- **EC2 instance role (`EC2InstanceRole`)**: needs read access to the workflow package and write access to step outputs under `githubactions/*`.
- **S3 bucket versioning**: optional. When versioning is enabled, the S3 version ID of the package ZIP is recorded in `workflow-package.json`.
