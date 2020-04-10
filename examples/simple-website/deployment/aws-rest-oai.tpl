openapi: 3.0.1
info:
  title: ${project}APIGateway
  version: lQ7wIyxGvblIltvKOkLL
paths:
  /:
    get:
      responses:
        200:
          description: 'OK'
          headers:
            Content-Type: { schema: {} }
            Content-Length: { schema: {} }
            Timestamp: { schema: {} }
      x-amazon-apigateway-integration:
        responses:
          default:
            statusCode: '200'
            responseParameters:
              method.response.header.Content-Type: 'integration.response.header.Content-Type'
              method.response.header.Content-Length: 'integration.response.header.Content-Length'
              method.response.header.Timestamp: 'integration.response.header.Date'
        credentials: ${s3_read_object_role_arn}
        uri: 'arn:aws:apigateway:${s3_region}:s3:path/${s3_bucket}/${s3_serverless_folder}/statics/index.html'
        passthroughBehavior: when_no_match
        httpMethod: GET
        type: aws
  /api/ping:
    x-amazon-apigateway-any-method:
      isDefaultRoute: true
      x-amazon-apigateway-integration:
        responses:
          default:
            statusCode: '200'
        type: aws_proxy
        httpMethod: POST
        credentials: ${lambda_excution_role_arn}
        uri: 'arn:aws:apigateway:${apigateway_region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${lambda_region}:${account_id}:function:${project}ApiPingHandler:$${stageVariables.build_id}/invocations'
        connectionType: INTERNET
        payloadFormatVersion: 2
