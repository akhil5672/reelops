variable "region" {
  type    = string
  default = "us-east-1"
}
variable "environments" {
  description = "One ingest lane per app environment. Both run on the same dev cluster."
  type = map(object({
    retention_days = number
    redis_db       = number
  }))
  default = {
    staging = { retention_days = 3, redis_db = 0 }
    prod    = { retention_days = 7, redis_db = 1 }
  }
}
