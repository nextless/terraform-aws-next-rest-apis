# Tests

This folder contains automated tests for this Module. All of the tests are written in [Go](https://golang.org/). 
Most of these are "integration tests" that deploy real infrastructure using Terraform and verify that infrastructure 
works as expected using a helper library called [Terratest](https://github.com/gruntwork-io/terratest).  


## Running the tests

### Prerequisites

- Install the latest version of [Go](https://golang.org/).
- Install [dep](https://github.com/golang/dep) for Go dependency management.
- Install [Terraform](https://www.terraform.io/downloads.html).
- Install [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html)
- Configure your AWS credentials using one of the [options supported by the AWS 
  SDK](http://docs.aws.amazon.com/sdk-for-java/v1/developer-guide/credentials.html). Usually, the easiest option is to
  set the `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` environment variables.

### One-time setup

Download Go dependencies using dep:

```
cd test
dep ensure
```


### Run all the tests

```bash
cd test
go test -v -timeout 60m
```


### Run a specific test

To run a specific test called `TestFoo`:

```bash
cd test
go test -v -timeout 60m -run TestFoo
```
