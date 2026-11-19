terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # bucket / region / use_lockfile come from backend.hcl (written by the bootstrap stack).
  backend "s3" {
    key = "foundation/terraform.tfstate"
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "cloud-platform-lab"
      Module    = "00-foundation"
      ManagedBy = "terraform"
    }
  }
}
