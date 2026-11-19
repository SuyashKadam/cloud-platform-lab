terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    key = "github-oidc/terraform.tfstate"
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "cloud-platform-lab"
      Module    = "01-github-oidc"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  state_bucket = "cpl-tfstate-${data.aws_caller_identity.current.account_id}-${var.region}"

  # The "sub" (subject) claim GitHub puts in the token. Only tokens from this repo AND this branch
  # may assume the role. A workflow on any other branch, fork or repo gets AccessDenied.
  allowed_subject = "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${var.github_branch}"
}

# 1. Tell AWS to trust tokens issued by GitHub Actions.
#    One per AWS account; if it already exists, import it instead (see README).
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # AWS validates GitHub's certificate through its own trusted CA list nowadays, so these values
  # are not actually checked, but some tooling still expects them to be present.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

# 2. The role a workflow becomes. The trust policy decides WHO can assume it.
resource "aws_iam_role" "github_actions" {
  name                 = "cpl-github-actions"
  max_session_duration = 3600 # credentials expire after at most 1 hour

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          # The token was requested for AWS STS, not some other audience.
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          # ...and it comes from exactly this repo + branch.
          "token.actions.githubusercontent.com:sub" = local.allowed_subject
        }
      }
    }]
  })
}

# 3. What the role can DO once assumed. Deliberately small (least privilege): it can look at the
#    lab's VPCs and list the state bucket, nothing else. Later modules attach more as they need it.
resource "aws_iam_role_policy" "github_actions_readonly" {
  name = "cpl-readonly-demo"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DescribeVpcs"
        Effect   = "Allow"
        Action   = ["ec2:DescribeVpcs", "ec2:DescribeSubnets"]
        Resource = "*" # Describe* calls don't support resource-level restrictions
      },
      {
        Sid      = "ListStateBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::${local.state_bucket}"
      }
    ]
  })
}
