#!/usr/bin/env bash
set -euo pipefail

# . ./01_cloud_practitioner/use-course-profile.sh - before running the below script run this command ( with the leading dot to prevent a subshell)

# ====== Config (edit if you like) ======
REGION="${REGION:-eu-west-2}"
KEY_NAME="${KEY_NAME:-mlops-finance-key}"
SG_NAME="${SG_NAME:-mlops-finance-sg}"
INSTANCE_NAME="${INSTANCE_NAME:-mlops-finance-ec2}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t2.micro}"
PEM_FILE="${PEM_FILE:-${KEY_NAME}.pem}"

echo "Region: $REGION"
echo "Key:    $KEY_NAME"
echo "SG:     $SG_NAME"
echo "Name:   $INSTANCE_NAME"
echo "Type:   $INSTANCE_TYPE"
echo

# ====== Find latest Amazon Linux 2023 AMI (x86_64) ======
AMI_ID="$(aws ec2 describe-images \
  --region "$REGION" \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023*" "Name=architecture,Values=x86_64" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)"

if [[ "$AMI_ID" == "None" || -z "$AMI_ID" ]]; then
  echo "Could not find an Amazon Linux 2023 AMI in $REGION" >&2
  exit 1
fi
echo "Using AMI: $AMI_ID"
echo

# ====== Create key pair if missing ======
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "Key pair '$KEY_NAME' already exists, skipping create."
else
  echo "Creating key pair '$KEY_NAME'..."
  aws ec2 create-key-pair \
    --region "$REGION" \
    --key-name "$KEY_NAME" \
    --query 'KeyMaterial' \
    --output text > "$PEM_FILE"
  chmod 400 "$PEM_FILE"
  echo "Saved private key to: $PEM_FILE"
fi
echo

# ====== Get default VPC ======
VPC_ID="$(aws ec2 describe-vpcs --region "$REGION" --query 'Vpcs[0].VpcId' --output text)"
echo "Default VPC: $VPC_ID"
echo

# ====== Create security group if missing ======
if aws ec2 describe-security-groups --region "$REGION" --group-names "$SG_NAME" >/dev/null 2>&1; then
  echo "Security group '$SG_NAME' already exists, skipping create."
else
  echo "Creating security group '$SG_NAME'..."
  aws ec2 create-security-group \
    --region "$REGION" \
    --group-name "$SG_NAME" \
    --description "EC2 SG for SSH from my IP" \
    --vpc-id "$VPC_ID" >/dev/null
fi

# Authorize SSH from your current public IP (idempotent - ignore if exists)
MYIP="$(curl -s https://checkip.amazonaws.com)"
echo "Authorizing SSH (22) from $MYIP/32 ..."
aws ec2 authorize-security-group-ingress \
  --region "$REGION" \
  --group-name "$SG_NAME" \
  --protocol tcp --port 22 --cidr "$MYIP/32" >/dev/null 2>&1 || true
echo

# ====== Run instance ======
echo "Launching instance..."
INSTANCE_ID="$(aws ec2 run-instances \
  --region "$REGION" \
  --image-id "$AMI_ID" \
  --count 1 \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-groups "$SG_NAME" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}}]" \
  --query 'Instances[0].InstanceId' \
  --output text)"

echo "Instance ID: $INSTANCE_ID"
echo "Waiting for instance to enter 'running' state..."
aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"

# ====== Fetch public DNS ======
PUBLIC_DNS="$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicDnsName' \
  --output text)"

echo
echo "✅ Instance is running."
echo "Name:   $INSTANCE_NAME"
echo "ID:     $INSTANCE_ID"
echo "DNS:    $PUBLIC_DNS"
echo
echo "SSH command:"
echo "  ssh -i \"$PEM_FILE\" ec2-user@$PUBLIC_DNS"
echo
echo "Tip: to stop later:"
echo "  aws ec2 stop-instances --region $REGION --instance-ids $INSTANCE_ID"
echo "To terminate:"
echo "  aws ec2 terminate-instances --region $REGION --instance-ids $INSTANCE_ID"

# # make it executable (optional)
# chmod +x 01_cloud_practitioner/launch_ec2_al2023.sh

# # run with defaults (eu-west-2, t2.micro)
# ./01_cloud_practitioner/launch_ec2_al2023.sh

# # or override via env vars
# REGION=eu-west-1 KEY_NAME=mykey SG_NAME=my-sg INSTANCE_NAME=my-ec2 ./launch_ec2_al2023.sh