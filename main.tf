data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  exec_roles = [
    { name = "${var.project}LambdaExecRole", principal = "lambda.amazonaws.com" },
    { name = "${var.project}ApiGatewayInvokeLambdaRole", principal = "apigateway.amazonaws.com" },
    { name = "${var.project}ApiGatewayGetS3ObjectRole", principal = "apigateway.amazonaws.com" },
  ]
  s3_serverless_folder = "serverless"
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

locals {
  // @todo Support customize lambda exec role arn
  lambda_exec_role       = aws_iam_role.serverless_roles[0]
  api_invoke_lambda_role = aws_iam_role.serverless_roles[1]
  api_get_s3_object_role = aws_iam_role.serverless_roles[2]
}

resource "aws_s3_bucket" "serverless" {
  bucket        = var.s3_bucket_name
  acl           = "private"
  force_destroy = true

  lifecycle_rule {
    enabled = true
    id      = "functions_zip_files"
    prefix  = "serverless/functions/"

    expiration {
      days = 1
    }
  }
}

resource "null_resource" "serverless" {
  triggers = {
    build_id = var.aws_api_apis_build_id
  }

  provisioner "local-exec" {
    working_dir = "${var.next_dist_dir}/nextless"
    command     = "aws s3 cp ./ s3://${aws_s3_bucket.serverless.id}/serverless --recursive --region ${data.aws_region.current.name}"
  }
}

resource "aws_lambda_function" "apis" {
  for_each      = var.aws_api_apis_functions
  function_name = "${var.project}${each.key}"

  s3_bucket  = aws_s3_bucket.serverless.id
  s3_key     = "${local.s3_serverless_folder}/${each.value}"
  publish    = true
  handler    = "index.handler"
  runtime    = "nodejs12.x"
  role       = local.lambda_exec_role.arn
  depends_on = [null_resource.serverless]
}

resource "aws_iam_role_policy_attachment" "attach_lambda_basic_policy" {
  role       = local.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

// Previous lambda alias should not be deleted when deploying
// Blocked by https://github.com/hashicorp/terraform/issues/15485
// @todo aviod deleting previous alias by using local-exec as a workaround
resource "aws_lambda_alias" "apis" {
  for_each         = var.aws_api_apis_functions
  name             = var.aws_api_apis_build_id
  function_name    = aws_lambda_function.apis[each.key].arn
  function_version = aws_lambda_function.apis[each.key].version
}

data "aws_iam_policy_document" "allow_gateway_invoce_lambdas" {
  statement {
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = [
      "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${var.project}*"
    ]
  }
}

resource "aws_iam_policy" "allow_gateway_invoce_lambdas" {
  name        = "${var.project}ApiGatewayInvokeLambdasPolicy"
  description = "Allow S3:GetObject permission for API Gateway"

  policy = data.aws_iam_policy_document.allow_gateway_invoce_lambdas.json
}

resource "aws_iam_role_policy_attachment" "attach_lambda_invoke_policy" {
  role       = local.api_invoke_lambda_role.name
  policy_arn = aws_iam_policy.allow_gateway_invoce_lambdas.arn
}

data "aws_iam_policy_document" "allow_gateway_access_s3" {
  statement {
    actions = [
      "s3:GetObject"
    ]
    resources = [
      "arn:aws:s3:::${aws_s3_bucket.serverless.id}/${local.s3_serverless_folder}/statics/*"
    ]
  }
}

resource "aws_iam_policy" "allow_gateway_access_s3" {
  name        = "${var.project}ApiGatewayGetStaticPagePolicy"
  description = "Allow S3:GetObject permission for API Gateway"

  policy = data.aws_iam_policy_document.allow_gateway_access_s3.json
}

resource "aws_iam_role_policy_attachment" "attach_s3_readObject_policy" {
  role       = local.api_get_s3_object_role.name
  policy_arn = aws_iam_policy.allow_gateway_access_s3.arn
}

data "template_file" "api-gateway" {
  template = file(var.openapi_tpl_path)
  vars = {
    region               = data.aws_region.current.name
    s3_bucket            = aws_s3_bucket.serverless.id
    s3_serverless_folder = local.s3_serverless_folder
    account_id           = data.aws_caller_identity.current.account_id
    project              = var.project

    lambda_excution_role_arn = local.api_invoke_lambda_role.arn
    s3_read_object_role_arn  = local.api_get_s3_object_role.arn
  }
}

resource "aws_api_gateway_rest_api" "primary" {
  name = "${var.project}APiGateway"
  body = data.template_file.api-gateway.rendered

  endpoint_configuration {
    types = [var.gateway_endpoint_type]
  }
}

resource "aws_api_gateway_deployment" "primary" {
  rest_api_id       = aws_api_gateway_rest_api.primary.id
  stage_name        = var.api_gateway_deploy_stage
  stage_description = "Deployed at ${timestamp()}"

  variables = merge(
    var.api_gateway_deploy_variables,
    { build_id = var.aws_api_apis_build_id }
  )

  lifecycle {
    create_before_destroy = true
  }
}
