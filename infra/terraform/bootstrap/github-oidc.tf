# GitHub Actions gets short-lived AWS credentials via OIDC. No access keys stored in GitHub.
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}

data "aws_iam_policy_document" "gha_trust" {
  for_each = {
    push = "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/main"
    plan = "repo:${var.github_owner}/${var.github_repo}:pull_request"
  }
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [each.value]
    }
  }
}

# Role 1: main branch only -> push images to ECR
resource "aws_iam_role" "gha_ecr_push" {
  name               = "${var.project}-gha-ecr-push"
  assume_role_policy = data.aws_iam_policy_document.gha_trust["push"].json
}

data "aws_iam_policy_document" "ecr_push" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart",
      "ecr:DescribeImages", "ecr:DescribeImageScanFindings",
    ]
    resources = [for r in aws_ecr_repository.svc : r.arn]
  }
}

resource "aws_iam_role_policy" "gha_ecr_push" {
  role   = aws_iam_role.gha_ecr_push.id
  policy = data.aws_iam_policy_document.ecr_push.json
}

# Role 2: pull requests -> read-only, for `terraform plan`
resource "aws_iam_role" "gha_tf_plan" {
  name               = "${var.project}-gha-tf-plan"
  assume_role_policy = data.aws_iam_policy_document.gha_trust["plan"].json
}

resource "aws_iam_role_policy_attachment" "gha_tf_plan_ro" {
  role       = aws_iam_role.gha_tf_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "state_read" {
  statement {
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
  }
  # ReadOnlyAccess can't read secret values; plan needs it to refresh the app-config secret versions
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${var.region}:${local.account_id}:secret:reelops/*"]
  }
}

resource "aws_iam_role_policy" "gha_tf_plan_state" {
  role   = aws_iam_role.gha_tf_plan.id
  policy = data.aws_iam_policy_document.state_read.json
}
