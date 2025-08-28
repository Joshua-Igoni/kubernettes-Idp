output "cluster_name" { value = module.eks.cluster_name }
output "region"       { value = var.aws_region }
output "ecr_repo_url" { value = aws_ecr_repository.app.repository_url }
output "kubeconfig"   {
  value = jsonencode({
    name     = module.eks.cluster_name
    endpoint = module.eks.cluster_endpoint
    ca       = module.eks.cluster_certificate_authority_data
  })
  sensitive = true
}
