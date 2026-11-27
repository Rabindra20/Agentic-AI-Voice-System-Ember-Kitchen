locals {
  envs_observability = {
    demo = {
      alarm_email                  = "rabindrasah@lftechnology.com"
      log_retention_days           = 14
      lambda_duration_threshold_ms = 25000
    }
  }
  observability_config = local.envs_observability[var.env]
}
