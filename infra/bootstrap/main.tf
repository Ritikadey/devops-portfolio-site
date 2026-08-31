# Run this ONCE, manually, before anything else in infra/.
# It creates the S3 bucket + DynamoDB table that the main Terraform
# configuration uses as its remote state backend. Chicken-and-egg problem:
# state storage can't be defined inside the state it stores, so it lives
# in its own tiny, rarely-touched configuration.
#
# Usage:
#   cd infra/bootstrap
#   terraform init
#   terraform apply -var="project_name=devops-portfolio" -var="aws_region=ap-south-1"

terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "project_name" {
  type        = string
  description = "Short project slug used to name resources."
  default     = "devops-portfolio"
}

variable "aws_region" {
  type        = string
  description = "AWS region for the state bucket / lock table."
  default     = "ap-south-1"
}

resource "random_id" "suffix" {
  byte_length = 3
}

resource "aws_s3_bucket" "tf_state" {
  bucket = "${var.project_name}-tfstate-${random_id.suffix.hex}"

  tags = {
    Project = var.project_name
    Purpose = "terraform-remote-state"
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tf_lock" {
  name         = "${var.project_name}-tf-lock"
  billing_mode = "PAY_PER_REQUEST" # Free Tier: 25 GB always-free, no capacity to forget
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project = var.project_name
    Purpose = "terraform-state-lock"
  }
}

output "state_bucket_name" {
  value = aws_s3_bucket.tf_state.id
}

output "lock_table_name" {
  value = aws_dynamodb_table.tf_lock.name
}

output "backend_config_snippet" {
  description = "Paste these values into infra/backend.hcl"
  value = <<-EOT
    bucket         = "${aws_s3_bucket.tf_state.id}"
    key            = "devops-portfolio/terraform.tfstate"
    region         = "${var.aws_region}"
    dynamodb_table = "${aws_dynamodb_table.tf_lock.name}"
    encrypt        = true
  EOT
}
