locals {
  envs_lambda = {
    demo = {
      runtime     = "python3.12"
      timeout     = 30
      memory_size = 128
      embedding = {
        timeout     = 60
        memory_size = 1024
      }
    }
  }
  lambda_config = local.envs_lambda[var.env]
}
