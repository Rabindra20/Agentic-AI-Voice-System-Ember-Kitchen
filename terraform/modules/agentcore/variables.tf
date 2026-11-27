variable "prefix"               { type = string }
variable "env_config"           { type = any }
variable "ecr_agent_image_uri"  { type = string }
variable "account_id"           { type = string }
variable "aws_region"           { type = string }
variable "guardrail_id"         { type = string }
variable "guardrail_version"    { type = string }
variable "tool_lambda_arns"     { type = map(string) }
variable "tool_names" {
  type    = list(string)
  default = []
}
variable "embedding_lambda_arn" { type = string }
