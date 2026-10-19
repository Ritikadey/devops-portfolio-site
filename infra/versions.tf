terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.69"
    }
  }

  # Backend is configured partially here and completed at `terraform init
  # -backend-config=backend.hcl` (see infra/backend.hcl.example and the
  # bootstrap/ module that creates the bucket + lock table).
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# us-east-1 is required for ACM certificates used by CloudFront, regardless
# of which region the rest of the stack lives in.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
