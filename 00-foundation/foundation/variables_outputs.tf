variable "region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "alert_email" {
  description = "Email address for budget alerts"
  type        = string
}

variable "monthly_budget_usd" {
  type    = string
  default = "20"
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "private_route_table_id" {
  value = aws_route_table.private.id
}

output "kms_key_arn" {
  value = aws_kms_key.main.arn
}

output "kms_alias" {
  value = aws_kms_alias.main.name
}
