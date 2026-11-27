locals {
  envs_connect = {
    demo = {
      instance_alias         = "Rabindra-emberkitchen-demo"
      inbound_calls_enabled  = true
      outbound_calls_enabled = false
      general_queue_max      = 10
      emergency_queue_max    = 5
    }
  }
  connect_config = local.envs_connect[var.env]
}
