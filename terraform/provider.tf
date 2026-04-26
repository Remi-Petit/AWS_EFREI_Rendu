terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "myapp-terraform-state-355033546957"
    key            = "terraform.tfstate"
    region         = "eu-west-3"
    dynamodb_table = "myapp-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}
