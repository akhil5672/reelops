data "aws_caller_identity" "me" {}

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "reelops-tfstate-${data.aws_caller_identity.me.account_id}"
    key    = "dev/network.tfstate"
    region = var.region
  }
}

locals {
  net = data.terraform_remote_state.network.outputs
}

# ---------- S3 + SQS + DLQ per environment ----------
module "ingest" {
  source   = "../../../modules/ingest-queue"
  for_each = var.environments

  bucket_name    = "reelops-raw-${each.key}-${data.aws_caller_identity.me.account_id}"
  queue_name     = "reelops-ingest-${each.key}"
  retention_days = each.value.retention_days
}

# ---------- ElastiCache Redis (status store), private subnets only ----------
resource "aws_security_group" "redis" {
  name        = "reelops-dev-redis"
  description = "Redis reachable only from inside the VPC"
  vpc_id      = local.net.vpc_id

  ingress {
    description = "Redis from VPC"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [local.net.vpc_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "reelops-dev-redis"
  subnet_ids = local.net.private_subnets
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "reelops-dev"
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = "cache.t4g.micro"
  num_cache_nodes      = 1
  port                 = 6379
  parameter_group_name = "default.redis7"
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.redis.id]
}

# ---------- Infra -> app handoff ----------
# Terraform writes each environment's config to Secrets Manager.
# External Secrets Operator syncs it into a Kubernetes Secret, so nobody copies endpoints by hand.
resource "aws_secretsmanager_secret" "app_config" {
  for_each                = var.environments
  name                    = "reelops/${each.key}/app-config"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "app_config" {
  for_each  = var.environments
  secret_id = aws_secretsmanager_secret.app_config[each.key].id
  secret_string = jsonencode({
    AWS_REGION = var.region
    RAW_BUCKET = module.ingest[each.key].bucket_name
    QUEUE_URL  = module.ingest[each.key].queue_url
    REDIS_HOST = aws_elasticache_cluster.redis.cache_nodes[0].address
    REDIS_PORT = "6379"
    REDIS_DB   = tostring(each.value.redis_db)
  })
}
