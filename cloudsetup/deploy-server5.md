# Deploy main to server5

The GitHub Actions workflow `.github/workflows/deploy-server5.yml` is manually
triggered. It always checks out `main`, archives its tracked files, uploads the
archive to S3, starts the EC2 instance whose Name tag is `server5`, waits for SSM,
and sends an `AWS-RunPowerShellScript` command to replace
`C:\DEER\deer-cloud-compute-setup`.

## Configuration

Configure these repository Actions variables before running the workflow:

| Variable | Required | Value |
| --- | --- | --- |
| `AWS_REGION` | No | `us-east-1` |
| `AWS_DEPLOY_ROLE_ARN` | Yes | `${AWS_DEPLOY_ROLE_ARN}` |
| `DEPLOY_BUCKET` | Yes | `${DEPLOY_BUCKET}` |

The workflow uses GitHub OIDC, not stored AWS access keys. The role's live trust
policy must allow this repository. The exported policy in
`role_GitHubSimulationRole.json` currently only lists
`simularis/DEER-Prototypes-EnergyPlus`; add the following subject to its
`token.actions.githubusercontent.com:sub` allowlist, retaining the existing
audience restriction and any subjects still needed:

```text
repo:simularis/deer-cloud-compute-setup:ref:refs/heads/main
```

Use the actual repository owner/name if different. Run the workflow from the
`main` branch to match this trust restriction.

The deployment role needs `s3:PutObject` under the bucket's
`githubactions/deploy-server5/*` prefix, `ec2:DescribeInstances`,
`ec2:StartInstances`, `ssm:DescribeInstanceInformation`, `ssm:SendCommand`,
`ssm:ListCommandInvocations`, and `ssm:GetCommandInvocation`.
The exported simulation-role policy conditions SSM access on simulation EC2 tags;
that permission is not sufficient for an arbitrary `server5` instance. Add a
separate permission for this deployment rather than changing server5's workload
tags. For example, attach this policy to the deployment role, substituting the
actual region, account ID, and server5 instance ID:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ssm:SendCommand",
      "Resource": [
        "arn:aws:ssm:REGION::document/AWS-RunPowerShellScript",
        "arn:aws:ec2:REGION:ACCOUNT_ID:instance/SERVER5_INSTANCE_ID"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["ssm:ListCommandInvocations", "ssm:GetCommandInvocation"],
      "Resource": "*"
    }
  ]
}
```

The server needs AWS CLI on the SYSTEM account's PATH, a running SSM Agent with
its normal managed-instance permissions, and an instance role allowing
`s3:GetObject` for the deployment prefix. Its network must reach S3 and SSM.
The existing `custom-policy_SimulationS3Access.json` covers this S3 prefix.
Repository policy exports are documentation; changing them does not update IAM.

## Run

Commit the workflow to `main`, then open **Actions > Deploy main to server5 >
Run workflow**, select `main`, and run. The job logs the deployed commit, SSM
command ID, and remote stdout/stderr, and fails if the remote command fails.

Only one deployment runs at a time. Download and extraction finish before the
existing folder is moved aside. If installing the staged folder fails, the
previous folder is restored. A failed deployment does not stop the instance.

The replacement removes ALL previous folder contents, including `.git`, local
edits, ignored files, and generated outputs. Pause simulations or other processes
using this folder before deploying. Keep persistent data outside the repo.
The deployed folder is a source snapshot, not a Git clone, and this workflow does
not run installers or restart applications. The instance remains running after
deployment. Archives remain in S3 under a unique run/attempt/commit key; configure
an S3 lifecycle rule for this prefix if retention needs to be limited.