terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.70" }
  }
  backend "s3" {
    bucket         = "reelops-tfstate-743157045351"
    key            = "dev/data.tfstate"
    region         = "us-east-1"
    dynamodb_table = "reelops-tf-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { project = "reelops", env = "dev", stack = "data", managed_by = "terraform" }
  }
}
