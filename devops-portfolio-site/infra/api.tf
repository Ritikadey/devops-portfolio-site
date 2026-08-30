# ---------------------------------------------------------------------------
# DynamoDB — on-demand, single item counter. No capacity to over-provision.
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "visitors" {
  name         = "${var.project_name}-visitors"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  point_in_time_recovery {
    enabled = false # skip for a portfolio project to avoid any edge-case charges
  }
}

# ---------------------------------------------------------------------------
# ECR — private repo for the Lambda container image
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "visitor_api" {
  name                 = "${var.project_name}/visitor-api"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "visitor_api" {
  repository = aws_ecr_repository.visitor_api.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the 5 most recent images (stay under Free Tier storage)"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

# ---------------------------------------------------------------------------
# Lambda — container image, deployed from ECR
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "visitor_api" {
  function_name = "${var.project_name}-visitor-api"
  role          = aws_iam_role.lambda_exec.arn
  package_type  = "Image"
  image_uri     = var.lambda_image_uri
  timeout       = 5
  memory_size   = 128 # smallest size — plenty for this workload, keeps well within free compute time

  environment {
    variables = {
      VISITORS_TABLE = aws_dynamodb_table.visitors.name
      ALLOWED_ORIGIN = var.allowed_cors_origin
    }
  }

  lifecycle {
    ignore_changes = [image_uri] # CI updates the running image directly; Terraform owns everything else
  }
}

resource "aws_cloudwatch_log_group" "visitor_api" {
  name              = "/aws/lambda/${aws_lambda_function.visitor_api.function_name}"
  retention_in_days = 14 # avoid unbounded log storage growth
}

# ---------------------------------------------------------------------------
# API Gateway — HTTP API (cheaper + simpler than REST API)
# ---------------------------------------------------------------------------
resource "aws_apigatewayv2_api" "visitor_api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = [var.allowed_cors_origin]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["content-type"]
  }
}

resource "aws_apigatewayv2_integration" "visitor_api" {
  api_id                 = aws_apigatewayv2_api.visitor_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.visitor_api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "visitors" {
  api_id    = aws_apigatewayv2_api.visitor_api.id
  route_key = "POST /visitors"
  target    = "integrations/${aws_apigatewayv2_integration.visitor_api.id}"
}

resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.visitor_api.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.visitor_api.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.visitor_api.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 20
    throttling_rate_limit  = 10 # small, intentional throttle — a portfolio API doesn't need headroom for a traffic spike, and this bounds worst-case invocations
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format          = jsonencode({
      requestId = "$context.requestId"
      ip        = "$context.identity.sourceIp"
      method    = "$context.httpMethod"
      path      = "$context.path"
      status    = "$context.status"
      latency   = "$context.responseLatency"
    })
  }
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name              = "/aws/apigateway/${var.project_name}"
  retention_in_days = 14
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.visitor_api.execution_arn}/*/*"
}
