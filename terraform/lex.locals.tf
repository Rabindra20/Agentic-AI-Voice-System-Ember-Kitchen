locals {
  envs_lex = {
    demo = {
      locale_id                   = "en_GB"
      voice_id                    = "Amy"
      idle_session_ttl_in_seconds = 300
      nlu_confidence_threshold    = 0.70
    }
  }
  lex_config = local.envs_lex[var.env]
}
