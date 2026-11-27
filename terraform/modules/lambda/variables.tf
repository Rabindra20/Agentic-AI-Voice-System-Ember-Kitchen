variable "prefix"                  { type = string }
variable "env_config"              { type = any }
variable "ecr_embedding_image_uri" { type = string }
variable "reservations_table_name" { type = string }
variable "reservations_table_arn"  { type = string }
variable "call_log_table_name"     { type = string }
variable "call_log_table_arn"      { type = string }
variable "qdrant_endpoint"         { type = string }
variable "connect_instance_id" {
  type    = string
  default = ""
}
variable "connect_domain_id" {
  type    = string
  default = ""
}
