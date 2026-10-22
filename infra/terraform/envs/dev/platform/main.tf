data "aws_caller_identity" "me" {}

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "reelops-tfstate-${data.aws_caller_identity.me.account_id}"
    key    = "dev/network.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "data" {
  backend = "s3"
  config = {
    bucket = "reelops-tfstate-${data.aws_caller_identity.me.account_id}"
    key    = "dev/data.tfstate"
    region = var.region
  }
}

locals {
  net   = data.terraform_remote_state.network.outputs
  lanes = data.terraform_remote_state.data.outputs.lanes
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = local.net.vpc_id
  subnet_ids = local.net.private_subnets

  # Public endpoint so kubectl works from your laptop. Lock it to your IP for extra safety:
  # cluster_endpoint_public_access_cidrs = ["<your-ip>/32"]
  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
  }

  eks_managed_node_groups = {
    # Argo CD, Prometheus, controllers, ingest-api
    system = {
      instance_types = ["t3.large"]
      min_size       = 2
      max_size       = 3
      desired_size   = 2
    }
    # Transcode workers on cheap Spot capacity. Taint keeps everything else off.
    transcode = {
      instance_types = ["t3.medium", "t3a.medium"]
      capacity_type  = "SPOT"
      min_size       = 0
      max_size       = 3
      desired_size   = 1
      labels         = { workload = "transcode" }
      taints = {
        spot = { key = "spot", value = "true", effect = "NO_SCHEDULE" }
      }
    }
  }
}
