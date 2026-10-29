# Repository Security and Operational-Detail Sanitization

This document defines what may be committed to this repository, what must be sanitized, and where secrets and environment-specific operational configuration should be stored.

## Core rule

Treat the repository as if it is already public.

Do not commit credentials, secret values, private keys, production resource inventories, or raw cloud-account exports. A private repository reduces exposure but does not make committed sensitive data an appropriate secret store. Repository history, forks, caches, artifacts, logs, and future visibility changes can preserve information after a file is deleted.

Commit reusable code, schemas, policy templates, and sanitized examples. Keep live values in the system that uses them.

## Information classification

### 1. Secrets: never commit

Never commit any value that authenticates a person, workload, application, or system, including:

- Passwords and recovery codes
- AWS access-key IDs and secret access keys
- Temporary security credentials or session tokens
- GitHub, API, OAuth, or personal access tokens
- Private SSH keys, EC2 key-pair material, or private certificates
- Database credentials and connection strings containing credentials
- Webhook secrets, signing keys, encryption keys, and shared secrets
- Password-manager exports
- Decrypted secret-manager data
- Credentials copied into logs, test fixtures, notebooks, screenshots, or examples

If a secret is committed, assume it is compromised. Revoke or rotate it first, then remove it from the working tree and repository history.

### 2. Sensitive operational detail: do not commit raw

The following values are not necessarily credentials, but raw exports can disclose identities, attack surface, deployment history, or a detailed infrastructure map:

- AWS account IDs and account-specific ARNs
- Real IAM role, user, group, instance-profile, and SSO principal identifiers
- S3 bucket names and production object prefixes
- VPC, subnet, route-table, internet-gateway, NAT-gateway, VPN, peering, and VPC-endpoint inventories
- CIDR blocks, internal DNS names, public IP addresses, Elastic IP addresses, and customer-gateway addresses
- Security-group and network ACL IDs or complete rules
- AMI, snapshot, launch-template, instance, volume, and network-interface IDs
- EC2 key-pair names
- CloudWatch log-group and log-stream names when account-specific
- SSM command IDs, instance IDs, and command output containing environment values
- Names or identifiers of individual administrators in generated metadata
- Raw `CreatedBy`, ownership, audit, or deployment-history fields
- Production tags that disclose customers, owners, internal projects, environments, expiration rules, or cost allocation
- Raw IAM policy exports when they include production resource ARNs or reveal broadly scoped permission paths
- Raw Terraform state, CloudFormation deployment outputs, or similar state files

Store raw inventories outside the repository. If they are required for operations, keep them in the cloud account, an approved restricted document location, or an encrypted administrative archive with access controls and retention rules.

### 3. Usually safe after review

The following are normally suitable for a public repository when they contain no embedded live values:

- Source code and scripts that accept configuration through parameters
- JSON Schema and validation rules
- Generic architecture diagrams
- Example manifests with fictitious data
- Parameterized IAM and infrastructure-as-code templates
- Service names and high-level descriptions of responsibilities
- EC2 instance-family or sizing profiles when they do not identify live resources
- Redacted logs and status examples
- Placeholder resource identifiers
- Public software download URLs and published checksums

"Not a credential" does not automatically mean "appropriate to publish." Review combinations of details that could reconstruct the production environment.

## Required sanitization

Replace live values with clear placeholders. Prefer semantic placeholders rather than shortened real values.

| Live-value category | Use a placeholder such as |
|---|---|
| AWS account ID | `${AWS_ACCOUNT_ID}` |
| Region | `${AWS_REGION}` |
| Role ARN | `${GITHUB_SIMULATION_ROLE_ARN}` |
| Instance profile | `${EC2_INSTANCE_PROFILE_NAME}` |
| S3 bucket | `${SIMULATION_BUCKET}` |
| S3 run prefix | `${RUN_PREFIX}` |
| VPC ID | `${VPC_ID}` |
| Subnet ID | `${SUBNET_ID}` |
| Security group ID | `${SECURITY_GROUP_ID}` |
| Launch template ID | `${LAUNCH_TEMPLATE_ID}` |
| AMI ID | `${AMI_ID}` |
| Snapshot ID | `${SNAPSHOT_ID}` |
| Key-pair name | `${EC2_KEY_PAIR_NAME}` |
| Public or private IP | `${IP_ADDRESS}` |
| CIDR block | `${NETWORK_CIDR}` |
| Named human principal | `${DEPLOYER_PRINCIPAL}` |

Do not preserve the length, prefix, suffix, or recognizable fragments of a sensitive value unless the format itself is necessary for the example.

## Cloud-export policy

### Commit

- Export scripts that contain no credentials or live identifiers
- Allowlists of resource types or fields to export
- Schemas describing expected export structure
- Sanitization scripts
- Sanitized examples created for documentation or tests

### Do not commit

- Raw output from `describe-*`, `list-*`, or `get-*` commands against a production account
- Complete VPC and network-topology exports
- Launch-template version history
- IAM exports containing account-specific resources or principal identifiers
- SSO and audit metadata
- Raw instance, image, snapshot, volume, endpoint, VPN, or gateway inventories

Generated raw exports should go to a gitignored directory, for example:

```text
cloudsetup/private/
cloudsetup/raw/
```

Recommended `.gitignore` entries:

```gitignore
# Raw cloud-account exports
cloudsetup/private/
cloudsetup/raw/
cloudsetup/generated/

# Local secret and environment files
.env
.env.*
!.env.example
*.pem
*.key
*.p12
*.pfx
secrets.*
!secrets.example.*

# Infrastructure state and plans
*.tfstate
*.tfstate.*
*.tfplan
```

A `.gitignore` entry prevents new accidental additions. It does not remove files already present in repository history.

## Secrets and configuration storage

Do not create a plaintext `secrets` file in the repository.

Use the storage location that matches the consumer:

- **Cloud workloads:** Use the cloud provider's identity and secret/configuration services. Prefer workload identity and temporary credentials over stored long-lived access keys.
- **GitHub Actions:** Prefer OIDC and narrowly scoped cloud roles. Use GitHub environment or repository secrets only for values that cannot be obtained through workload identity.
- **Human-access credentials:** Store them in the organization's approved password manager.
- **Non-secret runtime configuration:** Store it in managed configuration, deployment variables, or environment-specific configuration outside the public repository.
- **Local development:** Use an ignored `.env` or local configuration file populated from the approved source. Commit only `.env.example` or a sample configuration containing placeholders.

The repository includes a secret-name manifest (config-manifest.example.yaml) that documents required keys without storing their values, for example:

```yaml
requiredConfiguration:
  - AWS_REGION
  - SIMULATION_BUCKET
  - EC2_LAUNCH_TEMPLATE_ID
  - EC2_SUBNET_ID

requiredSecrets: []
```

For the current AWS workflow, OIDC and IAM roles should eliminate the need for AWS access keys in GitHub. Resource identifiers such as bucket, launch-template, and subnet values should be supplied through controlled variables or managed configuration rather than a committed secret file.

## Logging and artifacts

Before publishing logs, transcripts, workflow summaries, screenshots, notebooks, or artifacts, inspect them for:

- Environment-variable values
- Command arguments containing credentials
- Presigned URLs and query strings
- Bucket names and object paths
- Account IDs and ARNs
- Instance, subnet, security-group, launch-template, AMI, and snapshot IDs
- Public IPs, internal hostnames, and network ranges
- Usernames, email addresses, and SSO session identifiers
- Repository URLs that embed credentials
- Error messages that echo configuration or request headers

Do not pass secrets in command-line arguments. Avoid printing complete environment blocks. Redact before upload to GitHub Actions artifacts, S3, CloudWatch, or issue attachments.

## Automated scanning with Gitleaks

The repository's `gitleaks.toml` extends Gitleaks' built-in credential rules
with patterns for AWS account IDs in ARNs and owner fields, common AWS resource
IDs, IAM unique IDs, and concrete S3 bucket ARNs. The rules describe formats;
they do not contain live account or resource values. Review findings before
allowlisting them. Keep `--redact` enabled, and do not publish raw Gitleaks
reports because report files may contain matched values.

With Docker installed, run these commands from the repository root in
PowerShell. The first scans the current Git diff; the second scans commit
history and can reveal previously committed values:

```powershell
docker run --rm -v "${PWD}:/path" zricethezav/gitleaks:v8.30.1 git --pre-commit --verbose --redact --config=/path/gitleaks.toml /path
docker run --rm -v "${PWD}:/path" zricethezav/gitleaks:v8.30.1 git --verbose --redact --config=/path/gitleaks.toml /path
```

The Git-based scans use repository changes and history rather than walking
ignored local files such as `.env`. Gitleaks returns a nonzero exit code when it
finds a match. Historical findings require review and may persist until the
repository history is remediated.

The `Sensitive data scan` GitHub Actions workflow runs the same versioned image
on pull requests and pushes to `main`. It scans only commits in the event's
range, except for an initial push where it scans all available history. Open
the workflow run's **Scan secrets and AWS identifiers** step to see verbose,
redacted findings, including the rule ID, file, line, and fingerprint. The
workflow has read-only repository permissions; matched values remain redacted.

## Pull-request checklist

Before merging a change that touches cloud configuration, confirm:

- [ ] No credentials, tokens, private keys, certificates, or passwords are present.
- [ ] No raw production cloud exports are included.
- [ ] Account IDs, ARNs, bucket names, resource IDs, network details, key-pair names, and human principal names are replaced with placeholders where publication is unnecessary.
- [ ] IAM examples are parameterized and have been reviewed for least privilege.
- [ ] Logs, screenshots, notebooks, fixtures, and generated artifacts have been reviewed, not only source files.
- [ ] Local secret and export paths are covered by `.gitignore`.
- [ ] Example files use synthetic values and cannot operate against production without explicit configuration.
- [ ] Automated secret scanning and dependency/security checks pass.
- [ ] The change remains safe if the repository becomes public immediately.

## Incident response for an accidental commit

1. Revoke or rotate exposed credentials immediately. Do not wait for repository cleanup.
2. Determine whether sensitive operational details require resource renaming, policy changes, network-rule changes, or monitoring.
3. Remove the material from the current branch and repository history where appropriate.
4. Review forks, releases, workflow artifacts, caches, issues, pull requests, and external mirrors.
5. Document what was exposed, when it was exposed, and the remediation completed.
6. Add preventive controls such as ignore rules, secret scanning, pre-commit checks, and safer export defaults.

## Default decision rule

When unsure whether a value belongs in the repository:

1. Keep the live value in the cloud account, approved password manager, or managed configuration system.
2. Put only the variable name, schema, or sanitized example in the repository.
3. Obtain a security review before publishing the raw value.
