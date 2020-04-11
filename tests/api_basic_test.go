package test

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/aws"
	http_helper "github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

func TestNextlessAwsRestApiBasicUsage(t *testing.T) {
	t.Parallel()
	project := fmt.Sprintf("NextlessAwesome%s", random.UniqueId())
	s3BucketName := fmt.Sprintf("nextless%s", strings.ToLower(random.UniqueId()))

	rootDir := test_structure.CopyTerraformFolderToTemp(t, "..", "/")
	exampleDir := fmt.Sprintf("%s/examples/simple-website", rootDir)

	s3Folder := "serverless"
	region := aws.GetRandomStableRegion(t, nil, nil)
	stageName := random.UniqueId()

	defer emptyAndDeleteS3Bucket(t, region, s3BucketName)
	aws.CreateS3Bucket(t, region, s3BucketName)

	uploadFolderToS3(t, region, s3BucketName, fmt.Sprintf("%s/dist", exampleDir), s3Folder)

	terraformOptions := &terraform.Options{
		TerraformDir: rootDir,

		Vars: map[string]interface{}{
			"region":        region,
			"lambda_region": region,
			"s3_region":     region,
			"project":       project,

			"s3_serverless_folder":  s3Folder,
			"static_s3_bucket_name": s3BucketName,

			"openapi_tpl_path":         fmt.Sprintf("%s/deployment/aws-rest-oai.tpl", exampleDir),
			"api_gateway_deploy_stage": stageName,
		},

		EnvVars: map[string]string{
			"AWS_DEFAULT_REGION": region,
		},

		VarFiles: []string{fmt.Sprintf("%s/deployment/aws-rest-apis-nextless.tfvars", exampleDir)},
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	retries := 5
	sleep := 3 * time.Second

	url := terraform.Output(t, terraformOptions, "api_gateway_deployment_invoke_url")
	http_helper.HttpGetWithRetry(t, url, nil, 200, "<main>Hello Index</main>", retries, sleep)
	http_helper.HttpGetWithRetry(t, fmt.Sprintf("%s/api/ping", url), nil, 200, "Hello World", retries, sleep)
}
