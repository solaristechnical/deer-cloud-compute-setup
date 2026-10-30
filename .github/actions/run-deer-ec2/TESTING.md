# Running the offline test

The test script extracts the four Bash steps from `action.yml`, syntax-checks
them, and runs them against mocked AWS CLI calls. It does not submit AWS
requests or require AWS credentials. Bash, `jq`, and mikefarah `yq` v4 are
required.

The harness also extracts the workflow's matrix-generation script and checks
scenario numbering, names containing spaces and quotes, and invalid inventories.
It locates the workflow relative to this action directory, or via `WORKFLOW_FILE`.

Run the commands below from the repository root unless a command says
otherwise.

## Linux

On Ubuntu or Debian, install the system prerequisites:

```bash
sudo apt-get update
sudo apt-get install -y bash ca-certificates curl jq
```

Install the mikefarah `yq` v4 binary:

```bash
YQ_VERSION=v4.44.3
sudo curl -fsSL \
  "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" \
  -o /usr/local/bin/yq
sudo chmod +x /usr/local/bin/yq
```

Confirm the prerequisites and run the test:

```bash
bash --version
jq --version
yq --version
bash .github/actions/run-deer-ec2/test.sh
```

## Windows with Docker

Start Docker Desktop and open PowerShell. The following command mounts the
repository read-only, installs prerequisites in a disposable Ubuntu container,
and runs the test there. Update `$repo` if your checkout is in another
location.

```powershell
$repo = 'C:\DEER2026\deer-cloud-compute-setup\deer-cloud-compute-setup'
docker run --rm -v "${repo}:/src:ro" ubuntu:24.04 bash -lc "set -e; apt-get update -qq; apt-get install -y -qq --no-install-recommends bash ca-certificates curl jq; curl -fsSL https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64 -o /usr/local/bin/yq; chmod +x /usr/local/bin/yq; mkdir -p /tmp/run-deer-ec2-test; tr -d '\r' < /src/.github/actions/run-deer-ec2/test.sh > /tmp/run-deer-ec2-test/test.sh; tr -d '\r' < /src/.github/actions/run-deer-ec2/action.yml > /tmp/run-deer-ec2-test/action.yml; WORKFLOW_FILE=/src/.github/workflows/deer_simulations.yml bash /tmp/run-deer-ec2-test/test.sh"
```

The temporary copies normalize Windows CRLF line endings to LF without
changing the checkout. This matters because Bash may reject a CRLF-terminated
script with an error such as `set: pipefail\r: invalid option name`.

The container needs internet access to install the prerequisites. Once they
are installed, the test itself uses only local files and mocked AWS commands.

## PowerShell Controller Test

Run the single-scenario controller regression test in PowerShell 7.3+ on Windows:

```powershell
./workflow/test-workflow-simulate.ps1
```

It mocks repository initialization, AWS, and simulation jobs. It checks exact
scenario selection, independent numbered status/manifest/summary keys, and
rejection of unknown scenario IDs without starting real simulations.

For developer linting and formatting, install PSScriptAnalyzer independently
of VS Code. Simulation instances do not need this development dependency:

```powershell
Install-Module PSScriptAnalyzer -RequiredVersion 1.24.0 -Scope CurrentUser -Repository PSGallery
```

## Deploying Scenario Simulations

Before enabling the matrix workflow, update the installed
`C:/DEER/deer-cloud-compute-setup/workflow/BootstrapSimulation.ps1` in the
simulation AMI to this version, then publish/select the updated launch-template
version. The installed bootstrap must accept `-ScenarioId` before it can
download the frozen workflow package. Updating the package alone is not enough.

Package QC exports one `simulate-N` matrix entry per scenario. Each job launches
its own EC2 instance; GitHub concurrency and AWS quotas determine how many
can start simultaneously. A failed scenario does not cancel its siblings.
Each job retains the existing instance cleanup inputs.

Under `githubactions/<run-id>/`, transcripts use
`attempt-<attempt>/transcript_simulate-N.log`, status and controller metadata
use `steps/simulate-N/`, and logs use `outputs/simulate-N/<scenario-id>/`.
Large simulation results retain `simulate/<scenario-id>/runs/` for resume and
downstream processing. Per-scenario manifests and summaries do not overwrite
the shared compose/QC metadata. Start a new workflow run to use the new package;
re-running an older run reuses its frozen package.
