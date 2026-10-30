# Running the offline test

The test script extracts the four Bash steps from `action.yml`, syntax-checks
them, and runs them against mocked AWS CLI calls. It does not submit AWS
requests or require AWS credentials. Bash, `jq`, and mikefarah `yq` v4 are
required.

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
docker run --rm -v "${repo}:/src:ro" ubuntu:24.04 bash -lc "set -e; apt-get update -qq; apt-get install -y -qq --no-install-recommends bash ca-certificates curl jq; curl -fsSL https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64 -o /usr/local/bin/yq; chmod +x /usr/local/bin/yq; mkdir -p /tmp/run-deer-ec2-test; tr -d '\r' < /src/.github/actions/run-deer-ec2/test.sh > /tmp/run-deer-ec2-test/test.sh; tr -d '\r' < /src/.github/actions/run-deer-ec2/action.yml > /tmp/run-deer-ec2-test/action.yml; bash /tmp/run-deer-ec2-test/test.sh"
```

The temporary copies normalize Windows CRLF line endings to LF without
changing the checkout. This matters because Bash may reject a CRLF-terminated
script with an error such as `set: pipefail\r: invalid option name`.

The container needs internet access to install the prerequisites. Once they
are installed, the test itself uses only local files and mocked AWS commands.
