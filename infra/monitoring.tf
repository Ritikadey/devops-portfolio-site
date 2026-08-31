# ---------------------------------------------------------------------------
# SNS topic for all alerts (alarms + budget)
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------------------------------------------------------------------------
# CloudWatch alarms — free tier includes 10 alarms
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods   = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 3
  alarm_description   = "Visitor API Lambda has thrown more than 3 errors in 5 minutes."
  dimensions = {
    FunctionName = aws_lambda_function.visitor_api.function_name
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name          = "${var.project_name}-lambda-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods   = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Visitor API Lambda is being throttled — check concurrency."
  dimensions = {
    FunctionName = aws_lambda_function.visitor_api.function_name
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.project_name}-api-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods   = 1
  metric_name         = "5xx"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 3
  alarm_description   = "API Gateway is returning 5xx responses."
  dimensions = {
    ApiId = aws_apigatewayv2_api.visitor_api.id
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-overview"
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x = 0, y = 0, width = 12, height = 6
        properties = {
          title   = "Lambda invocations / errors"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.visitor_api.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.visitor_api.function_name]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
        }
      },
      {
        type   = "metric"
        x = 12, y = 0, width = 12, height = 6
        properties = {
          title   = "API Gateway requests / latency"
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", aws_apigatewayv2_api.visitor_api.id],
            ["AWS/ApiGateway", "Latency", "ApiId", aws_apigatewayv2_api.visitor_api.id]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
        }
      },
      {
        type   = "metric"
        x = 0, y = 6, width = 12, height = 6
        properties = {
          title   = "CloudFront requests"
          metrics = [
            ["AWS/CloudFront", "Requests", "DistributionId", aws_cloudfront_distribution.site.id, "Region", "Global"]
          ]
          period = 3600
          stat   = "Sum"
          region = "us-east-1"
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Cost guard — AWS Budgets alert (this is the real safety net for Free Tier)
# ---------------------------------------------------------------------------
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
