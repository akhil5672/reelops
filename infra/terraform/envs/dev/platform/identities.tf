# Pod Identity: each ServiceAccount gets exactly the AWS permissions it needs.
locals {
  # staging/ingest-api, staging/transcode-worker, prod/ingest-api, prod/transcode-worker
  app_workloads = merge([
    for env, lane in local.lanes : {
      "${env}-ingest-api" = {
        namespace = "reelops-${env}"
        sa        = "ingest-api"
        statements = [
          { actions = ["s3:PutObject"], resources = ["${lane.bucket_arn}/raw/*"] },
          { actions = ["sqs:SendMessage", "sqs:GetQueueAttributes"], resources = [lane.queue_arn] },
        ]
      }
      "${env}-transcode-worker" = {
        namespace = "reelops-${env}"
        sa        = "transcode-worker"
        statements = [
          { actions = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"], resources = [lane.queue_arn] },
          { actions = ["s3:GetObject"], resources = ["${lane.bucket_arn}/raw/*"] },
        ]
      }
    }
  ]...)
}

data "aws_iam_policy_document" "app" {
  for_each = local.app_workloads
  dynamic "statement" {
    for_each = each.value.statements
    content {
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

module "app_identity" {
  source   = "../../../modules/workload-role"
  for_each = local.app_workloads

  name            = "reelops-${each.key}"
  cluster_name    = module.eks.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.sa
  policy_json     = data.aws_iam_policy_document.app[each.key].json
}

# ---------- platform add-on identities ----------
module "lb_controller_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4"

  name                            = "reelops-aws-lbc"
  attach_aws_lb_controller_policy = true
  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}

module "external_secrets_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4"

  name                                  = "reelops-external-secrets"
  attach_external_secrets_policy        = true
  external_secrets_secrets_manager_arns = ["arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.me.account_id}:secret:reelops/*"]
  external_secrets_create_permission    = false
  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "external-secrets"
      service_account = "external-secrets"
    }
  }
}

# YACE exports CloudWatch metrics (SQS depth, DLQ, ALB 5xx) to Prometheus
data "aws_iam_policy_document" "yace" {
  statement {
    actions   = ["cloudwatch:GetMetricData", "cloudwatch:ListMetrics", "tag:GetResources", "sqs:ListQueues", "elasticloadbalancing:DescribeLoadBalancers"]
    resources = ["*"]
  }
}

module "yace_identity" {
  source          = "../../../modules/workload-role"
  name            = "reelops-yace"
  cluster_name    = module.eks.cluster_name
  namespace       = "monitoring"
  service_account = "yace"
  policy_json     = data.aws_iam_policy_document.yace.json
}
