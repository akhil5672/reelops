output "account_id" { value = local.account_id }
output "state_bucket" { value = aws_s3_bucket.state.bucket }
output "lock_table" { value = aws_dynamodb_table.lock.name }
output "ecr_repositories" { value = { for k, r in aws_ecr_repository.svc : k => r.repository_url } }
output "gha_ecr_push_role_arn" { value = aws_iam_role.gha_ecr_push.arn }
output "gha_tf_plan_role_arn" { value = aws_iam_role.gha_tf_plan.arn }
