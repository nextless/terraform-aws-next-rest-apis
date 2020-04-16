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
}

locals {
  serverless_bucket_path = "s3://${aws_s3_bucket.serverless.id}/serverless/${var.aws_api_apis_build_id}"
}

resource "null_resource" "serverless_assets" {
  triggers = {
    build_id = var.aws_api_apis_build_id
  }

  provisioner "local-exec" {
    working_dir = "${var.next_dist_dir}/nextless"
    command     = "aws s3 cp ./ ${local.serverless_bucket_path} --recursive --region ${data.aws_region.current.name}"
  }
  depends_on = [aws_s3_bucket.serverless]
}

resource "aws_lambda_function" "apis" {
  for_each      = var.aws_api_apis_functions
  function_name = "${var.project}${each.key}"

  s3_bucket  = aws_s3_bucket.serverless.id
  s3_key     = "${local.s3_serverless_folder}/${var.aws_api_apis_build_id}/${each.value}"
  publish    = true
  handler    = "index.handler"
  runtime    = "nodejs12.x"
  role       = local.lambda_exec_role.arn
  depends_on = [null_resource.serverless_assets]
}

resource "aws_iam_role_policy_attachment" "attach_lambda_basic_policy" {
  role       = local.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

// Aviod deleting previous alias by using local-exec as a workaround
resource "null_resource" "lambda_function_alias" {
  for_each = var.aws_api_apis_functions

  triggers = {
    build_id = var.aws_api_apis_build_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws lambda create-alias \
      --function-name ${aws_lambda_function.apis[each.key].arn} \
      --function-version ${aws_lambda_function.apis[each.key].version} \
      --description "alias for ${var.project} API Gateway" \
      --name ${var.aws_api_apis_build_id} \
      --region ${data.aws_region.current.name}
    EOT
  }
  depends_on = [aws_lambda_function.apis]
}

resource "null_resource" "remove_used_function_zips" {
  triggers = {
    build_id = var.aws_api_apis_build_id
  }

  provisioner "local-exec" {
    command = "aws s3 rm ${local.serverless_bucket_path}/functions --recursive --region ${data.aws_region.current.name}"
  }
  depends_on = [aws_lambda_function.apis]
}

data "aws_iam_policy_document" "allow_gateway_invoke_lambdas" {
  statement {
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = [
      "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${var.project}*"
    ]
  }
}

resource "aws_iam_policy" "allow_gateway_invoke_lambdas" {
  name        = "${var.project}ApiGatewayInvokeLambdasPolicy"
  description = "Allow S3:GetObject permission for API Gateway"

  policy = data.aws_iam_policy_document.allow_gateway_invoke_lambdas.json
}

resource "aws_iam_role_policy_attachment" "attach_lambda_invoke_policy" {
  role       = local.api_invoke_lambda_role.name
  policy_arn = aws_iam_policy.allow_gateway_invoke_lambdas.arn
}

data "aws_iam_policy_document" "allow_gateway_access_s3" {
  statement {
    actions = [
      "s3:GetObject"
    ]
    resources = [
      "arn:aws:s3:::${aws_s3_bucket.serverless.id}/${local.s3_serverless_folder}/*/statics/*"
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

  depends_on = [null_resource.lambda_function_alias, null_resource.serverless_assets]
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
