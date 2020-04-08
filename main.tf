data "aws_caller_identity" "current" {}

locals {
  exec_roles = [
    { name = "${var.project}LambdaExecRole", principal = "lambda.amazonaws.com" },
    { name = "${var.project}ApiGatewayInvokeLambdaRole", principal = "apigateway.amazonaws.com" },
    { name = "${var.project}ApiGatewayGetS3ObjectRole", principal = "apigateway.amazonaws.com" },
  ]
}

data "aws_iam_policy_document" "serverless_roles" {
  count = length(local.exec_roles)

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = [local.exec_roles[count.index].principal]
    }
  }
}

resource "aws_iam_role" "serverless_roles" {
  count = length(local.exec_roles)
  name  = local.exec_roles[count.index].name

  assume_role_policy = data.aws_iam_policy_document.serverless_roles[count.index].json
}


// Both of the lambda_function and alias should not be deleted when deploying
// Blocked by https://github.com/hashicorp/terraform/issues/15485
resource "aws_lambda_function" "apis" {
  for_each      = var.aws_api_apis_functions
  function_name = each.key

  s3_bucket = var.static_s3_bucket_name
  s3_key    = "${var.s3_serverless_folder}/${each.value}"
  publish   = true
  handler   = "index.handler"
  runtime   = "nodejs12.x"
  role      = aws_iam_role.serverless_roles[0].arn
}

// @todo aviod deleting previous alias by using local-exec as a workaround
resource "aws_lambda_alias" "apis" {
  for_each         = var.aws_api_apis_functions
  name             = var.aws_api_apis_build_id
  function_name    = aws_lambda_function.apis[each.key].arn
  function_version = aws_lambda_function.apis[each.key].version
}

locals {
  lambdas_arns = [for k, v in var.aws_api_apis_functions : "arn:aws:lambda:${var.lambda_region}:${data.aws_caller_identity.current.account_id}:function:${k}"]
}

data "aws_iam_policy_document" "allow_gateway_invoce_lambdas" {
  statement {
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = local.lambdas_arns
  }
}

resource "aws_iam_policy" "allow_gateway_invoce_lambdas" {
  name        = "${var.project}ApiGatewayInvokeLambdasPolicy"
  description = "Allow S3:GetObject permission for API Gateway"

  policy = data.aws_iam_policy_document.allow_gateway_invoce_lambdas.json
}

resource "aws_iam_role_policy_attachment" "attach_lambda_invoke_policy" {
  role       = aws_iam_role.serverless_roles[1].name
  policy_arn = aws_iam_policy.allow_gateway_invoce_lambdas.arn
}

data "aws_iam_policy_document" "allow_gateway_access_s3" {
  statement {
    actions = [
      "s3:GetObject"
    ]
    resources = [
      "arn:aws:s3:::${var.static_s3_bucket_name}/${var.s3_serverless_folder}/static/*"
    ]
  }
}

resource "aws_iam_policy" "allow_gateway_access_s3" {
  name        = "${var.project}ApiGatewayGetStaticPagePolicy"
  description = "Allow S3:GetObject permission for API Gateway"

  policy = data.aws_iam_policy_document.allow_gateway_access_s3.json
}

resource "aws_iam_role_policy_attachment" "attach_s3_readObject_policy" {
  role       = aws_iam_role.serverless_roles[2].name
  policy_arn = aws_iam_policy.allow_gateway_access_s3.arn
}

data "template_file" "api-gateway" {
  template = file(var.openapi_tpl_path)
  vars = {
    apigateway_region    = var.region
    lambda_region        = var.lambda_region
    s3_region            = var.s3_region
    s3_bucket            = var.static_s3_bucket_name
    s3_serverless_folder = var.s3_serverless_folder
    account_id           = data.aws_caller_identity.current.account_id

    lambda_excution_role_arn = aws_iam_role.serverless_roles[1].arn
    s3_read_object_role_arn  = aws_iam_role.serverless_roles[2].arn
  }
}

resource "aws_api_gateway_rest_api" "primary" {
  name       = "VincentuAPiGateway"
  body       = data.template_file.api-gateway.rendered
  depends_on = [aws_lambda_function.apis]

  endpoint_configuration {
    types = [var.gateway_endpoint_type]
  }
}

resource "aws_api_gateway_deployment" "primary" {
  depends_on = [aws_lambda_function.apis]

  rest_api_id       = aws_api_gateway_rest_api.primary.id
  stage_name        = var.api_gateway_deploy_stage
  stage_description = "Deployed at ${timestamp()}"

  lifecycle {
    create_before_destroy = true
  }
}
