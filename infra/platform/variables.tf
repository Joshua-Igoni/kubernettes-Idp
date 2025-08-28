variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "kubernettes-idp"
}

variable "ecr_repo_url" {
  type = string
} # pass from infra output

variable "app_tag" {
  type    = string
  default = "main"
}
