output "bucket_name" { value = aws_s3_bucket.raw.bucket }
output "bucket_arn" { value = aws_s3_bucket.raw.arn }
output "queue_url" { value = aws_sqs_queue.main.url }
output "queue_arn" { value = aws_sqs_queue.main.arn }
output "queue_name" { value = aws_sqs_queue.main.name }
output "dlq_name" { value = aws_sqs_queue.dlq.name }
output "dlq_arn" { value = aws_sqs_queue.dlq.arn }
