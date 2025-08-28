variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "kubernettes-idp"
}

variable "node_count" {
  type    = number
  default = 2
}

variable "node_type" {
  type    = string
  default = "t3.large"
}

variable "ecr_repo_name" {
  type    = string
  default = "kubernettes-sample"
}
