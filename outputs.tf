output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.primary.id
  description = "The ID of the REST API"
}

output "api_gateway_root_resource_id" {
  value       = aws_api_gateway_rest_api.primary.root_resource_id
  description = "The resource ID of the REST API's root"
}

output "api_gateway_root_resource_arn" {
  value       = aws_api_gateway_rest_api.primary.arn
  description = "Amazon Resource Name (ARN) of the REST API"
}

output "api_gateway_deployment_id" {
  value       = aws_api_gateway_deployment.primary.id
  description = "The ID of the deployment"

}

output "api_gateway_deployment_invoke_url" {
  value       = aws_api_gateway_deployment.primary.invoke_url
  description = "The URL to invoke the API pointing to the stage"

}

output "api_gateway_deployment_execution_arn" {
  value       = aws_api_gateway_deployment.primary.execution_arn
  description = "The execution ARN to be used in lambda_permission's source_arn when allowing API Gateway to invoke a Lambda function"
}

output "lambda_exec_role_name" {
  value       = local.lambda_exec_role.name
  description = "The name of IAM role attached to the Lambda Function"
}

output "lambda_exec_role_arn" {
  value       = local.lambda_exec_role.arn
  description = "IAM role attached to the Lambda Function"
}

output "api_gateway_get_s3_role_name" {
  value       = local.api_get_s3_object_role.name
  description = "The name of IAM role used as the api_gateway_integration credentials for S3 service"
}

output "api_gateway_get_s3_role_arn" {
  value       = local.api_get_s3_object_role.arn
  description = "IAM role used as the api_gateway_integration credentials for S3 service"
}
