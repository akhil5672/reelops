variable "region" {
  type    = string
  default = "us-east-1"
}
variable "cluster_name" {
  type    = string
  default = "reelops-dev"
}
variable "kubernetes_version" {
  description = "Use a version EKS currently offers in standard support: aws eks describe-cluster-versions"
  type        = string
  default     = "1.37"
}
