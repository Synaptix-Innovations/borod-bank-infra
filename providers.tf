terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment to enable remote state storage:
  # backend "s3" {
  #   bucket         = "borod-bank-tfstate"
  #   key            = "eks/terraform.tfstate"
  #   region         = "eu-central-1"
  #   dynamodb_table = "borod-bank-tflock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}
