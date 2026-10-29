# Update the DEER AMI and launch template

The manually triggered workflow `.github/workflows/update-deer-ami.yml` creates
an AMI from a source EC2 instance, waits until it is available, and creates a
new version of the configured launch template with that AMI ID.

## Repository variables

Set these under **Settings > Secrets and variables > Actions > Variables**:

| Variable | Required | Default |
| --- | --- | --- |
| `AMI_SOURCE_INSTANCE_ID` | Yes | None |
| `AWS_REGION` | No | `us-east-1` |
| `AWS_DEPLOY_ROLE_ARN` | Yes | `${AWS_DEPLOY_ROLE_ARN}` |
| `EC2_LAUNCH_TEMPLATE_ID` | Yes | `${EC2_LAUNCH_TEMPLATE_ID}` |

Run **Actions > Update DEER AMI and launch template > Run workflow** from
`main`. The job uses GitHub OIDC; the role trust policy must allow this
repository's `repo:simularis/deer-cloud-compute-setup:ref:refs/heads/main`
subject (adjust the owner/repository if needed).

The run summary displays the new launch-template version number. Later steps in
the same job can read `steps.update-template.outputs.version-number`; dependent
jobs can read `needs.update-ami.outputs.launch-template-version` after declaring
`needs: update-ami`.

## AWS role permissions

The live role needs `ec2:CreateImage` on the source instance,
`ec2:DescribeImages` for the availability wait, and
`ec2:CreateLaunchTemplateVersion` on the target launch template. It also needs
`ec2:CreateTags` for the new image and snapshots; the checked-in role policy
export already lists that action, but the live role must be checked separately.
The launch template includes `EC2InstanceRole`, so retain the role's existing
`iam:PassRole` permission for that instance role.

The JSON files under `cloudsetup` are policy exports; editing them does not
change AWS IAM. Add permissions to the live role before running the workflow.