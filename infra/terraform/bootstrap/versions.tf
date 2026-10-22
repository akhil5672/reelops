terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.70" }
  }
  # Bootstrap uses LOCAL state on purpose: it creates the bucket the other stacks store state in.
  # Keep bootstrap/terraform.tfstate safe (it is git-ignored), or migrate it into the bucket later.
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { project = var.project, stack = "bootstrap", managed_by = "terraform" }
  }
}
