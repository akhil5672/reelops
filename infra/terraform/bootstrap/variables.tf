variable "region" {
  type    = string
  default = "us-east-1"
}
variable "project" {
  type    = string
  default = "reelops"
}
variable "github_owner" {
  type    = string
  default = "akhil5672"
}
variable "github_repo" {
  type    = string
  default = "reelops"
}
variable "alert_email" {
  description = "Where AWS Budgets sends cost alerts"
  type        = string
  default     = "akhilkumar5672@gmail.com"
}
variable "monthly_budget_usd" {
  type    = number
  default = 40
}
variable "ecr_repos" {
  type    = set(string)
  default = ["ingest-api", "transcode-worker"]
}
