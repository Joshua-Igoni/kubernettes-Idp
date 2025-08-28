terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Example ECR repo (optional if you already created it)
resource "aws_ecr_repository" "app" {
  name = var.ecr_repo_name
}

# CloudFront distribution with default domain (no custom cert)
resource "aws_cloudfront_distribution" "k8s_ingress" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "kubernettes-idp via NLB"

  # REQUIRED: origin NLB DNS
  origin {
    domain_name = var.origin_dns_name
    origin_id   = "k8s-ingress-nlb"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # start simple; can switch to https-only later
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "k8s-ingress-nlb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET","HEAD","OPTIONS","PUT","PATCH","POST","DELETE"]
    cached_methods         = ["GET","HEAD"]
    # For dynamic apps, disable caching by default (tune later)
    default_ttl            = 0
    min_ttl                = 0
    max_ttl                = 0
    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies { forward = "all" }
    }
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true  # uses *.cloudfront.net cert
  }

  price_class = "PriceClass_100"
}
