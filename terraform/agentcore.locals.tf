locals {
  envs_agentcore = {
    demo = {
      claude_model_id             = "anthropic.claude-haiku-20240307-v1:0"
      idle_session_ttl_in_seconds = 600
    }
  }
  agentcore_config = local.envs_agentcore[var.env]
}
