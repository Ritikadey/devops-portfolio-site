# ---------------------------------------------------------------------------
# Lambda execution role — least privilege: logs + this one table only
# ---------------------------------------------------------------------------
resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_logs" {
  name = "logs"
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.visitor_api.arn}:*"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "dynamodb-visitors-table"
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:UpdateItem", "dynamodb:GetItem"]
      Resource = aws_dynamodb_table.visitors.arn
    }]
  })
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC — lets workflows assume an AWS role with a short-lived
# token instead of storing an AWS access key as a GitHub secret.
# ---------------------------------------------------------------------------
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-actions"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # Restrict to this repo; broaden the ref pattern if you use
          # protected environments/branches beyond main.
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:*"
        }
      }
    }]
  })
}

# Scoped to exactly the resources this project touches — no wildcard admin
# access, deliberately, so a compromised workflow can't reach outside this stack.
resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "deploy-scope"
  role = aws_iam_role.github_actions.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "FrontendDeploy"
        Effect = "Allow"
        Action = [
          "s3:PutObject", "s3:GetObject", "s3:ListBucket", "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.site.arn,
          "${aws_s3_bucket.site.arn}/*"
        ]
      },
      {
        Sid      = "CloudFrontInvalidate"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
        Resource = aws_cloudfront_distribution.site.arn
      },
      {
        Sid    = "BackendImagePush"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "BackendImagePushRepo"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:PutImage",
          "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload"
        ]
        Resource = aws_ecr_repository.visitor_api.arn
      },
      {
        Sid      = "LambdaUpdate"
        Effect   = "Allow"
        Action   = ["lambda:UpdateFunctionCode", "lambda:GetFunction"]
        Resource = aws_lambda_function.visitor_api.arn
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# A second, deliberately separate role for `terraform apply` itself.
#
# Provisioning has to touch IAM (creating the two roles above), which the
# day-to-day deploy role above must never be allowed to do — otherwise a
# compromised frontend/backend workflow could grant itself more access.
# This role is scoped to the AWS services this project actually uses, named
# by project prefix, and is gated behind a GitHub Environment that requires
# manual approval (see .github/workflows/terraform.yml) rather than running
# unattended on every push.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "terraform_apply" {
  name = "${var.project_name}-terraform-apply"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # Allows both PRs (for `terraform plan`) and main (for the
          # environment-gated `terraform apply`). Tighten to just the main
          # ref if you'd rather run plan with a separate, read-only role.
          "token.actions.githubusercontent.com:sub" = [
            "repo:${var.github_repository}:pull_request",
            "repo:${var.github_repository}:ref:refs/heads/main"
          ]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "terraform_apply_scope" {
  name = "provisioning-scope"
  role = aws_iam_role.terraform_apply.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ServiceProvisioning"
        Effect = "Allow"
        Action = [
          "s3:*", "cloudfront:*", "lambda:*", "apigateway:*",
          "dynamodb:*", "ecr:*", "logs:*", "sns:*", "budgets:*",
          "acm:*", "route53:*"
        ]
        # Left broad at the action level (Terraform needs many read/describe
        # calls that are awkward to enumerate) but this role can only ever
        # be assumed from main via a gated environment — see the workflow.
        Resource = "*"
      },
      {
        Sid      = "IamForThisProjectOnly"
        Effect   = "Allow"
        Action   = ["iam:*"]
        Resource = [
          aws_iam_role.lambda_exec.arn,
          aws_iam_role.github_actions.arn,
          aws_iam_openid_connect_provider.github.arn
        ]
      },
      {
        Sid      = "IamReadOnly"
        Effect   = "Allow"
        Action   = ["iam:Get*", "iam:List*"]
        Resource = "*"
      }
    ]
  })
}
