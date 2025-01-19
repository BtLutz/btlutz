terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws" # Specify the source of the AWS provider
      version = "~> 4.0"        # Use a version of the AWS provider that is compatible with version
    }
    random = {
      source  = "hashicorp/random"
      version = "3.4.3"
    }
  }
  backend "remote" {
    organization = "TheLonelyGecko"

    workspaces {
      name = "btlutz"
    }
  }
}

provider "aws" {
  region = "us-east-1" # Set the AWS region to US East (N. Virginia)
}

resource "aws_ecr_repository" "btlutz" {
  name = "btlutz"
}