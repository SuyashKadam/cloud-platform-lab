variable "region" {
  type    = string
  default = "us-east-1"
}

variable "github_owner" {
  type    = string
  default = "SuyashKadam"
}

variable "github_repo" {
  type    = string
  default = "cloud-platform-lab"
}

variable "github_branch" {
  type    = string
  default = "main"
}

output "role_arn" {
  description = "Put this in the repo's Actions variable AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}

output "allowed_subject" {
  value = local.allowed_subject
}

output "state_bucket" {
  value = local.state_bucket
}
