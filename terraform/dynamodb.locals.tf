locals {
  envs_dynamodb = {
    demo = {
      reservations_table = "Reservations"
      call_log_table     = "CallLog"
      billing_mode       = "PAY_PER_REQUEST"
    }
  }
  dynamodb_config = local.envs_dynamodb[var.env]
}
