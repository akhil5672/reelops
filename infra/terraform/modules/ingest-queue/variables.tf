variable "bucket_name" { type = string }
variable "queue_name" { type = string }
variable "retention_days" {
  type    = number
  default = 7
}
variable "visibility_timeout_seconds" {
  description = "Must exceed the worker's longest job, or messages get processed twice"
  type        = number
  default     = 60
}
variable "max_receive_count" {
  type    = number
  default = 3
}
