# Get the public IP address of the local machine and
# authorize it for SSH and RDP access into the specified security group.
# Use this to enable developer access to EC2 instances from localhost.


# Read .env file from repository root
source .env

# Check if SECURITY_GROUP_ID variable is set
if (! $SECURITY_GROUP_ID) {
    Write-Host "SECURITY_GROUP_ID not set"
    # Enter SECURITY_GROUP_ID in your environment file or enter a group name here:
    SECURITY_GROUP_NAME = 'my-security-group'
    # Get the security group ID
    SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --group-names $SECURITY_GROUP_NAME --query 'SecurityGroups[0].GroupId' --output text)
}

IPADDRESS=$(curl -s https://checkip.amazonaws.com)
SYSTEM_NAME=$(hostname)

aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --ip-permissions '{"FromPort":22,"ToPort":22,"IpProtocol":"tcp","IpRanges":[{"CidrIp":"'$IPADDRESS'/32","Description":"'$SYSTEM_NAME'"}]}' '{"FromPort":3389,"ToPort":3389,"IpProtocol":"tcp","IpRanges":[{"CidrIp":"'$IPADDRESS'/32","Description":"'$SYSTEM_NAME'"}]}' 
