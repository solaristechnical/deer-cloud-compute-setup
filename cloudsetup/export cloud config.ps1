# Requires PowerShell 7.3+ (pwsh); Windows PowerShell 5.1 redirects output as UTF-16.

# This script exports the cloud configuration for AWS resources used in the DEER simulations.
# The JSON files in this folder were not written by hand, just exported using this script.

# Security:
# - Relevant objects should be tagged and filtered by the tag, e.g. Workload = RunDeerSimulations
# - everything network-related goes into the subfolder private, excluded by gitignore.
# - To provide examples for reference, manually redact/sanitize the private files and save in "example" folder.

# Developers may export files to the "private" for review and reference while developing locally.

$ErrorActionPreference = "Stop"

$export_destination_dir = ".\cloudsetup\private"
New-Item -ItemType Directory -Force -Path $export_destination_dir

# Export AWS IAM role policies
Write-Host "Exporting IAM role policies..."
aws iam list-role-policies --role-name GitHubSimulationRole --profile admin --output json > $export_destination_dir\role_GitHubSimulationRole_policies.json

Write-Host "Exporting EC2 info..."
aws iam get-role-policy --role-name GitHubSimulationRole --policy-name GitHubSimulationRolePolicy --profile admin > $export_destination_dir\custom-policy-GitHubSimulationRolePolicy.json

Write-Host "Exporting EC2 role policies..."
aws iam list-role-policies --role-name EC2InstanceRole --profile admin --output json > $export_destination_dir\role_EC2InstanceRole_policies.json

Write-Host "Exporting attached EC2 role policies..."
aws iam --profile admin list-attached-role-policies --role-name EC2InstanceRole > $export_destination_dir\role_EC2InstanceRole_attached_policies.json

# Export EC2 instance information on server archetypes, AMIs, and launch templates
# Only export info on servers with the tag Workload = RunDeerSimulations
Write-Host "Exporting instances..."
aws ec2 describe-instances --filters "Name=tag:Workload,Values=RunDeerSimulations" --output json > $export_destination_dir\instances.json

Write-Host "Exporting images..."
# Only export images tagged with Purpose = Run DEER simulations
aws ec2 describe-images --owners self --filters "Name=tag:Purpose,Values=Run DEER simulations" --output json > $export_destination_dir\images.json

Write-Host "Exporting launch templates..."
# Only export launch templates tagged by Workload = RunDeerSimulations
aws ec2 describe-launch-templates --filters "Name=tag:Workload,Values=RunDeerSimulations" --output json > $export_destination_dir\launch-templates.json

Write-Host "Exporting launch template versions..."
# Only export launch templates versions corresponding to launch templates tagged by Workload = RunDeerSimulations
# Read launch-template IDs from the sanitized local export before use.
# Read the launch template IDs from the previously exported launch templates JSON file
# TODO: handle the scenario when there is only one launch template ID, otherwise launchTemplateIds is just a single string.
$array = Get-Content -Raw -Path $export_destination_dir\launch-templates.json | ConvertFrom-Json
$launchTemplateIds = $array.LaunchTemplates | ForEach-Object { $_.LaunchTemplateId }
for ($i = 0; $i -lt $launchTemplateIds.Count; $i++) {
    $launchTemplateId = $launchTemplateIds[$i]
    aws ec2 describe-launch-template-versions --launch-template-id "$launchTemplateId" --output json > "$export_destination_dir\launch-template-versions_$launchTemplateId.json"
}

Write-Host "Exporting security groups..."
# Export security groups
# Only with the tag Workload = RunDeerSimulations
aws ec2 describe-security-groups --filters "Name=tag:Workload,Values=RunDeerSimulations" --output json > $export_destination_dir\security-groups.json

Write-Host "Exporting VPCs..."
# Export VPC information
aws ec2 describe-vpcs --filters "Name=tag:Workload,Values=RunDeerSimulations" --output json > $export_destination_dir\vpcs.json

Write-Host "Exporting subnets..."
# Export subnets information
aws ec2 describe-subnets --filters "Name=tag:Workload,Values=RunDeerSimulations" --output json > $export_destination_dir\subnets.json

Write-Host "Exporting route tables..."
# Export route tables information
aws ec2 describe-route-tables --filters "Name=tag:Workload,Values=RunDeerSimulations" --output json > $export_destination_dir\route-tables.json

Write-Host "Exporting internet gateways..."
# Export internet gateways information
aws ec2 describe-internet-gateways --filters "Name=tag:Workload,Values=RunDeerSimulations" --output json > $export_destination_dir\internet-gateways.json

Write-Host "Exporting NAT gateways..."
# Export NAT gateways information
# TODO: This command does not have a --filters option.
aws ec2 describe-nat-gateways --filters "Name=tag:Workload,Values=RunDeerSimulations" --output json > $export_destination_dir\nat-gateways.json

Write-Host "Exporting VPN connections..."
# Export VPN connections information
aws ec2 describe-vpn-connections --filters "Name=tag:Workload,Values=RunDeerSimulations" --output json > $export_destination_dir\vpn-connections.json

Write-Host "Exporting customer gateways..."
# Export customer gateways information
aws ec2 describe-customer-gateways --filters "Name=tag:Workload,Values=RunDeerSimulations" --output json > $export_destination_dir\customer-gateways.json

Write-Host "Exporting DHCP options..."
# Export DHCP options sets information
aws ec2 describe-dhcp-options --filters "Name=tag:Workload,Values=RunDeerSimulations" --output json > $export_destination_dir\dhcp-options.json

Write-Host "Exporting Elastic IPs..."
# Export Elastic IP addresses information
aws ec2 describe-addresses --filters "Name=tag:Workload,Values=RunDeerSimulations" --output json > $export_destination_dir\elastic-ip-addresses.json

Write-Host "Exporting VPC peering..."
# Export VPC peering connections information
aws ec2 describe-vpc-peering-connections --filters "Name=tag:Workload,Values=RunDeerSimulations" --output json > $export_destination_dir\vpc-peering-connections.json

Write-Host "Exporting VPN gateways..."
# Export VPN gateways information
aws ec2 describe-vpn-gateways --filters "Name=tag:Workload,Values=RunDeerSimulations" --output json > $export_destination_dir\vpn-gateways.json

Write-Host "Exporting network ACLs..."
# Export network ACLs information
aws ec2 describe-network-acls --filters "Name=tag:Workload,Values=RunDeerSimulations" --output json > $export_destination_dir\network-acls.json

Write-Host "Exporting VPC endpoints..."
# Export VPC endpoints information
aws ec2 describe-vpc-endpoints --filters "Name=tag:Workload,Values=RunDeerSimulations" --output json > $export_destination_dir\vpc-endpoints.json

Write-Host "Exporting flow logs..."
# Export flow logs information
# TODO: This command does not have a --filters option.
aws ec2 describe-flow-logs --filters "Name=tag:Workload,Values=RunDeerSimulations" --output json > $export_destination_dir\flow-logs.json

Write-Host "Exporting load balancers..."
# Export Elastic Load Balancers information
# TODO: This command does not have a --filters option.
aws elb describe-load-balancers --filters "Name=tag:Workload,Values=RunDeerSimulations" --output json > $export_destination_dir\load-balancers.json

Write-Host "Exporting load balancer v2..."
# Export Elastic Load Balancer v2 (Application/Network) information
# TODO: This command does not have a --filters option.
aws elbv2 describe-load-balancers --filters "Name=tag:Workload,Values=RunDeerSimulations" --output json > $export_destination_dir\load-balancers-v2.json

Write-Host "Exporting target groups..."
# Export Elastic Load Balancer v2 target groups information
# TODO: This command does not have a --filters option.
aws elbv2 describe-target-groups --filters "Name=tag:Workload,Values=RunDeerSimulations" --output json > $export_destination_dir\target-groups-v2.json

# Export Elastic Load Balancer v2 listeners information (N/A)
#aws elbv2 describe-listeners --output json > $export_destination_dir\listeners-v2.json

# Export Elastic Load Balancer v2 rules information (N/A)
#aws elbv2 describe-rules --output json > $export_destination_dir\rules-v2.json

# Export Elastic Load Balancer v2 certificates information (N/A)
#aws elbv2 describe-certificates --output json > $export_destination_dir\certificates-v2.json

# Export Elastic Load Balancer v2 rules for a specific listener information (N/A)
#aws elbv2 describe-listener-certificates --output json > $export_destination_dir\listener-certificates-v2.json