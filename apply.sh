#!/bin/bash
#
# This script initializes and applies the Terraform configuration to deploy SUSE AI.
# After the instance is created, it will automatically connect via SSH and stream
# the output of the installation script.
#
# Before running, ensure you have:
# 1. Set your AWS credentials as environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY).
# 2. Created a terraform.tfvars file with your specific configuration.
#

set -e

echo "Initializing Terraform..."
terraform init

echo "Applying Terraform configuration... This may take a few minutes."
terraform apply -auto-approve

echo "------------------------------------------------------------------"
echo "Instance created. Attempting to stream the installation log."
echo "Press Ctrl+C at any time to stop watching the log."
echo "------------------------------------------------------------------"

TFVARS_FILE="terraform.tfvars"

# Check if terraform.tfvars file exists
if [ ! -f "$TFVARS_FILE" ]; then
    echo "Error: $TFVARS_FILE not found. Cannot determine SSH key path."
    exit 1
fi

# Get the instance's public IP from Terraform output
INSTANCE_IP=$(terraform output -raw suse_ai_public_ip)

# Get the Rancher hostname from the .tfvars file
RANCHER_HOSTNAME=$(grep "rancher_hostname" "$TFVARS_FILE" | sed -E 's/.*= *//; s/"//g')

# Extract the private key path directly from the .tfvars file
PRIVATE_KEY_PATH_RAW=$(grep "private_key_path" "$TFVARS_FILE" | sed -E 's/.*= *//; s/"//g')

# This expands the '~' character to the user's home directory in a more robust way
EXPANDED_PRIVATE_KEY_PATH="${PRIVATE_KEY_PATH_RAW/#\~/$HOME}"

if [ -z "$INSTANCE_IP" ] || [ -z "$EXPANDED_PRIVATE_KEY_PATH" ]; then
    echo "Error: Could not get instance IP or determine private key path. Exiting."
    exit 1
fi

if [ -n "$RANCHER_HOSTNAME" ]; then
    echo "Rancher will be available at: https://$RANCHER_HOSTNAME"
fi

# Loop to wait for the SSH service to become available on the new instance
echo "Waiting for SSH to become available on $INSTANCE_IP..."
for i in {1..30}; do
    if ssh -i "$EXPANDED_PRIVATE_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ec2-user@$INSTANCE_IP "echo SSH is ready" >/dev/null 2>&1; then
        echo "SSH connection successful. Streaming /var/log/cloud-init-output.log..."
        # Connect and stream the log file. The `-t` flag forces a tty allocation, which helps with clean termination.
        ssh -i "$EXPANDED_PRIVATE_KEY_PATH" -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ec2-user@$INSTANCE_IP "sudo tail -f /var/log/cloud-init-output.log"
        exit 0
    fi
    echo "Still waiting for SSH... attempt $i of 30."
    sleep 10
done

echo "Error: Could not connect to the instance via SSH after multiple attempts."
echo "You can try connecting manually: ssh -i $EXPANDED_PRIVATE_KEY_PATH ec2-user@$INSTANCE_IP"
if [ -n "$RANCHER_HOSTNAME" ]; then
    echo "Once the installation is complete, access Rancher at: https://$RANCHER_HOSTNAME"
fi
exit 1
