# Bootstrap: the S3 bucket that holds Terraform state for every other stack in this repo.
#
# This stack is the only one that keeps its own state locally (terraform.tfstate in this folder),
# because the remote backend can't store state in a bucket that doesn't exist yet.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "cloud-platform-lab"
      Module    = "00-foundation/bootstrap"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  # Bucket names are global across all AWS accounts, so the account ID and region make it unique.
  state_bucket = "cpl-tfstate-${data.aws_caller_identity.current.account_id}-${var.region}"
}

resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket

  # Lab setting: lets `terraform destroy` remove the bucket even if it still holds state files.
  # In a real company this would be false, with deletion protected by policy.
  force_destroy = true
}

# Every write creates a new object version, so a corrupted or deleted state file can be recovered.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Refuse any request that isn't over HTTPS.
resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.state]
}

# Writes backend.hcl at the repo root. Every other stack runs
#   terraform init -backend-config=<path to repo root>/backend.hcl
# so the bucket name only lives in one place. The file is git-ignored (it contains your account ID).
resource "local_file" "backend_config" {
  filename = "${path.module}/../../backend.hcl"
  content  = <<-EOT
    bucket       = "${aws_s3_bucket.state.bucket}"
    region       = "${var.region}"
    encrypt      = true
    use_lockfile = true
  EOT
}
