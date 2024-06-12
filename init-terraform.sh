#!/bin/bash

cd backend_resources
terraform init -backend=false
terraform apply -auto-approve

# Get the current AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Set environment variables for Terraform backend
export TF_VAR_backend_bucket="${ACCOUNT_ID}-hellohippo-ecs-state-bucket"

cd ../terraform
# Replace placeholders in backend configuration file
cat > backend.tf <<EOL
terraform {
  backend "s3" {
    bucket         = "$TF_VAR_backend_bucket"
    key            = "global/s3/terraform.tfstate"
    region         = "sa-east-1"
    dynamodb_table = "hellohippo-ecs-terraform-locks"
  }
}
EOL

# Initialize Terraform
terraform init
