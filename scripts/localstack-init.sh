#!/bin/bash
# Runs inside LocalStack when it is ready. Mirrors what Terraform creates on AWS.
set -euo pipefail
awslocal s3 mb s3://reelops-raw-local
awslocal sqs create-queue --queue-name reelops-ingest-local-dlq
DLQ_ARN="arn:aws:sqs:us-east-1:000000000000:reelops-ingest-local-dlq"
awslocal sqs create-queue --queue-name reelops-ingest-local --attributes \
  "{\"VisibilityTimeout\":\"60\",\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"${DLQ_ARN}\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"}"
