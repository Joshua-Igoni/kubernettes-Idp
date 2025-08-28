terraform {
  backend "s3" {
    bucket         = "your-tf-state-bucket"
    key            = "kubernettes-idp/infra.tfstate"
    region         = "us-east-1"
    dynamodb_table = "your-tf-locks"
    encrypt        = true
  }
}
