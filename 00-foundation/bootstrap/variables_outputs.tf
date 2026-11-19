variable "region" {
  description = "AWS region for the whole lab"
  type        = string
  default     = "us-east-1"
}

output "state_bucket" {
  value = aws_s3_bucket.state.bucket
}

output "backend_config_file" {
  value = abspath(local_file.backend_config.filename)
}
