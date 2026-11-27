resource "aws_dynamodb_table" "reservations" {
  name         = "${var.prefix}-${var.env_config.reservations_table}"
  billing_mode = var.env_config.billing_mode
  hash_key     = "reservation_id"

  attribute {
    name = "reservation_id"
    type = "S"
  }

  attribute {
    name = "guest_phone"
    type = "S"
  }

  global_secondary_index {
    name            = "GuestPhoneIndex"
    hash_key        = "guest_phone"
    projection_type = "ALL"
  }

  tags = { Project = var.prefix }
}

resource "aws_dynamodb_table" "call_log" {
  name         = "${var.prefix}-${var.env_config.call_log_table}"
  billing_mode = var.env_config.billing_mode
  hash_key     = "call_id"

  attribute {
    name = "call_id"
    type = "S"
  }

  tags = { Project = var.prefix }
}
