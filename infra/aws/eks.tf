module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name    = var.cluster_name
  cluster_version = "1.29"
  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = concat(module.vpc.private_subnets, module.vpc.public_subnets)

  enable_irsa = true

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_type]
      desired_size   = var.node_count
      min_size       = var.node_count
      max_size       = var.node_count + 1
      disk_size      = 50
      subnet_ids     = module.vpc.private_subnets
    }
  }
}
