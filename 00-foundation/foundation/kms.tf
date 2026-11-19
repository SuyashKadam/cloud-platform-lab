# A customer-managed KMS key used to encrypt data in later modules (logs, OpenSearch, S3 documents).
#
# Difference from the default AWS-managed keys: you control the key policy (who may use it), you can
# turn on rotation, and every use is recorded in CloudTrail. Costs about $1/month while it exists.

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "main" {
  description             = "cloud-platform-lab main encryption key"
  enable_key_rotation     = true # new key material every year; old data stays decryptable
  deletion_window_in_days = 7    # minimum; on destroy the key is scheduled for deletion, not deleted at once

  # Key policy: the account (its IAM policies) controls access to the key. Without a statement like
  # this nobody, not even the account root, could manage the key.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EnableIAMPolicies"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })
}

resource "aws_kms_alias" "main" {
  name          = "alias/cpl-main"
  target_key_id = aws_kms_key.main.key_id
}
