variable "project_name" {
  type        = string
  description = "Short project slug used to name and tag resources."
  default     = "devops-portfolio"
}

variable "environment" {
  type        = string
  description = "Deployment environment name."
  default     = "prod"
}

variable "aws_region" {
  type        = string
  description = "Primary AWS region for compute/data resources."
  default     = "ap-south-1"
}

variable "domain_name" {
  type        = string
  description = "Optional custom domain (e.g. example.com). Leave empty to use the CloudFront default domain and skip Route 53 / ACM (keeps cost at $0)."
  default     = ""
}

variable "route53_zone_id" {
  type        = string
  description = "Existing Route 53 hosted zone ID, required only if domain_name is set."
  default     = ""
}

variable "github_repository" {
  type        = string
  description = "GitHub repo allowed to assume the deploy role via OIDC, in 'owner/repo' form."
}

variable "lambda_image_uri" {
  type        = string
  description = "ECR image URI:tag for the visitor-api Lambda. Set after the first backend image push; the CI pipeline updates this on every deploy."
}

variable "budget_limit_usd" {
  type        = number
  description = "Monthly AWS Budgets threshold in USD that triggers an email alert."
  default     = 2
}

variable "alert_email" {
  type        = string
  description = "Email address for budget and CloudWatch alarm notifications."
}

variable "allowed_cors_origin" {
  type        = string
  description = "Origin allowed to call the API (your CloudFront domain). '*' works for a portfolio but is looser than necessary."
  default     = "*"
}
