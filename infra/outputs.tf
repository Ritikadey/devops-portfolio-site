output "cloudfront_domain_name" {
  description = "The site's public URL (CloudFront default domain, unless a custom domain is configured)."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "cloudfront_distribution_id" {
  description = "Used by the frontend deploy workflow to invalidate the cache."
  value       = aws_cloudfront_distribution.site.id
}

output "s3_bucket_name" {
  description = "Used by the frontend deploy workflow as the sync target."
  value       = aws_s3_bucket.site.id
}

output "api_base_url" {
  description = "Base URL for the visitor-counter API (set as VITE_API_URL in the frontend build)."
  value       = aws_apigatewayv2_api.visitor_api.api_endpoint
}

output "ecr_repository_url" {
  description = "Used by the backend deploy workflow to push new images."
  value       = aws_ecr_repository.visitor_api.repository_url
}

output "lambda_function_name" {
  description = "Used by the backend deploy workflow to update the running image."
  value       = aws_lambda_function.visitor_api.function_name
}

output "github_actions_role_arn" {
  description = "Role ARN to put in the GitHub repo variable AWS_DEPLOY_ROLE_ARN."
  value       = aws_iam_role.github_actions.arn
}
