variable "your_name" {
  description = "Prefix for all resource names (e.g. john)"
  type        = string
  default     = "rabindra"
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "env" {
  description = "Deployment environment name (must match a key in each envs_* local map)"
  type        = string
  default     = "demo"
}
