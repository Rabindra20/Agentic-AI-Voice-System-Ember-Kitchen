locals {
  # ── Module toggles ──────────────────────────────────────────────────────────
  # Set any of these to false to skip deploying that component.
  enable_ecr           = true
  enable_vpc           = true
  enable_dynamodb      = true
  enable_connect       = true
  enable_lex           = true
  enable_guardrails    = true
  enable_rag           = true
  enable_lambda        = true
  enable_agentcore     = true
  enable_observability = true
}
