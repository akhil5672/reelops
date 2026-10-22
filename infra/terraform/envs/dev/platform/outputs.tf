output "cluster_name" { value = module.eks.cluster_name }
output "kubeconfig_command" { value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}" }
output "app_role_arns" { value = { for k, m in module.app_identity : k => m.role_arn } }
