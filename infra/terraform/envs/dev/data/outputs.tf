output "lanes" {
  value = {
    for env, m in module.ingest : env => {
      bucket_name = m.bucket_name
      bucket_arn  = m.bucket_arn
      queue_url   = m.queue_url
      queue_arn   = m.queue_arn
      queue_name  = m.queue_name
      dlq_name    = m.dlq_name
    }
  }
}
output "redis_host" { value = aws_elasticache_cluster.redis.cache_nodes[0].address }
