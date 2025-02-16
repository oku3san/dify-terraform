# provider.tf
provider "aws" {
  region = var.region
}

provider "aws" {
  alias  = "global"
  region = "us-east-1"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# variables.tf
variable "region" {
  description = "AWS region"
  default     = "ap-northeast-1"
}

variable "environment" {
  description = "環境名"
  default     = "production"
}

variable "project" {
  description = "プロジェクト名"
  default     = "dify"
}