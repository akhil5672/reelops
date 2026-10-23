data "aws_availability_zones" "available" { state = "available" }

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name            = var.name
  cidr            = var.cidr
  azs             = local.azs
  private_subnets = [for i, _ in local.azs : cidrsubnet(var.cidr, 4, i)]       # 10.20.0.0/20, 10.20.16.0/20
  public_subnets  = [for i, _ in local.azs : cidrsubnet(var.cidr, 8, 200 + i)] # 10.20.200.0/24, 10.20.201.0/24

  # Cost choice: one NAT gateway for both AZs. In production you'd use one per AZ.
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # Tags the AWS Load Balancer Controller uses to find subnets for ALBs
  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
}

# Free gateway endpoint: S3 traffic from private subnets skips the NAT gateway (saves NAT data charges)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids
}
