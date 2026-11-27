locals {
  envs_base = {
    demo = {
      aws_region = var.aws_region
      account_id = data.aws_caller_identity.current.account_id
    }
  }
  base_config = local.envs_base[var.env]
  prefix      = "${var.your_name}-EmberKitchen-${var.env}"
}
