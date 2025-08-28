terraform {
  required_providers {
    aws         = { source = "hashicorp/aws", version = "~> 5.0" }
    kubernetes  = { source = "hashicorp/kubernetes", version = "~> 2.33" }
    helm        = { source = "hashicorp/helm",       version = "~> 2.13" }
    kubectl     = { source = "gavinbunney/kubectl",  version = "~> 1.14" } # for Argo Application CRs (optional)
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
