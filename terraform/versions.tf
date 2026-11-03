terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Production state backend recommendation (uncomment and configure for remote state)
  # backend "s3" {
  #   bucket         = "my-organization-terraform-state"
  #   key            = "networking/vpc-endpoint-service/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}