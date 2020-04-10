package test

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/aws/aws-sdk-go/service/s3/s3manager"
	grunt_aws "github.com/gruntwork-io/terratest/modules/aws"
	"github.com/stretchr/testify/require"
)

func uploadFolderToS3(t *testing.T, region string, bucket string, localFolder string, s3Folder string) {
	sess, err := grunt_aws.NewAuthenticatedSession(region)
	require.NoError(t, err)
	uploader := s3manager.NewUploader(sess)

	filepath.Walk(localFolder,
		func(path string, info os.FileInfo, err error) error {
			require.NoError(t, err)
			if info.IsDir() {
				return nil
			}

			f, err := os.Open(path)
			require.NoError(t, err)
			relPath, err := filepath.Rel(localFolder, path)
			require.NoError(t, err)
			result, err := uploader.Upload(&s3manager.UploadInput{
				Bucket: aws.String(bucket),
				Key:    aws.String(fmt.Sprintf("%s/%s", s3Folder, relPath)),
				Body:   f,
			})
			require.NoError(t, err)
			fmt.Printf("file uploaded to, %s\n", result.Location)
			return nil
		})
}

func emptyAndDeleteS3Bucket(t *testing.T, region string, bucket string) {
	sess, err := grunt_aws.NewAuthenticatedSession(region)
	require.NoError(t, err)
	svc := s3.New(sess)
	iter := s3manager.NewDeleteListIterator(svc, &s3.ListObjectsInput{
		Bucket: aws.String(bucket),
	})
	err = s3manager.NewBatchDeleteWithClient(svc).Delete(aws.BackgroundContext(), iter)
	require.NoError(t, err)
	grunt_aws.DeleteS3Bucket(t, region, bucket)
}
