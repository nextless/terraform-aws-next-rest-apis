# REST API Gateway for NextLess

![Terraform Version](https://img.shields.io/badge/tf-%3E%3D0.12.0-blue.svg)

This module helps your deploy your [Next.js](https://nextjs.org/) application to the AWS Rest API Gateway.

For more information please refer to the [Nextless repo](https://github.com/nextless/nextless).

![architecture](https://raw.githubusercontent.com/nextless/aws-rest-apis/master/_docs/nextless-aws-rest-gateway.png)

## Features

* Create lambda functions from S3 bucket with current BUILD_ID as alias.
* Create necessary IAM roles for API Gateway to execute Lambda functions and read files from S3 Bucket. 
* Using OAI (OpenAPI Specification file) to create Rest API gateway.
* Create Deployment for API Gateway.

## License

Please see [LICENSE](https://github.com/nextless/aws-rest-apis/blob/master/LICENSE) for details on how the code in this repo is licensed.
