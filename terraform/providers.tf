terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = var.aws_profile
  region  = "us-east-1"
}

provider "kubernetes" {
  config_path    = var.k8s_config
  config_context = var.k8s_context
}
