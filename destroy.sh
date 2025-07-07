#!/bin/bash
#
# This script destroys all infrastructure created by the Terraform project.
# It will automatically approve the destruction.
#
# It reads AWS credentials from the 'terraform.tfvars' file and exports them
# to authenticate the AWS CLI for the pre-termination stop command.
#

set -e

TFVARS_FILE="terraform.tfvars"

# Check if terraform.tfvars file exists
if [ ! -f "$TFVARS_FILE" ]; then
    echo "Error: $TFVARS_FILE not found."
    echo "Please ensure the file exists and contains your AWS credentials, or set them as environment variables."
    exit 1
fi

echo "Extracting AWS credentials from $TFVARS_FILE..."

# Use grep and sed to extract the values, removing quotes and whitespace
AWS_ACCESS_KEY_ID=$(grep "aws_access_key" "$TFVARS_FILE" | sed -E 's/.*= *//; s/"//g')
AWS_SECRET_ACCESS_KEY=$(grep "aws_secret_key" "$TFVARS_FILE" | sed -E 's/.*= *//; s/"//g')

# Check if credentials were successfully extracted
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "Error: Could not extract AWS credentials from $TFVARS_FILE."
    echo "Please ensure 'aws_access_key' and 'aws_secret_key' are set in the file."
    exit 1
fi

# Export the credentials for the current shell session
export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY

echo "Credentials exported. Destroying all SUSE AI infrastructure..."
terraform destroy -auto-approve

echo "Infrastructure successfully destroyed."
