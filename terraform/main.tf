# ── ECR ───────────────────────────────────────────────────────────────────────
module "ecr" {
  count      = local.enable_ecr ? 1 : 0
  source     = "./modules/ecr"
  prefix     = local.prefix
  env_config = local.ecr_config
}

# ── VPC ───────────────────────────────────────────────────────────────────────
module "vpc" {
  count      = local.enable_vpc ? 1 : 0
  source     = "./modules/vpc"
  prefix     = local.prefix
  env_config = local.vpc_config
}

# ── DynamoDB (PAY_PER_REQUEST — zero cost at rest) ────────────────────────────
module "dynamodb" {
  count      = local.enable_dynamodb ? 1 : 0
  source     = "./modules/dynamodb"
  prefix     = local.prefix
  env_config = local.dynamodb_config
}

# ── Amazon Lex V2 (free tier: 10k text / 5k voice per month) ─────────────────
module "lex" {
  count      = local.enable_lex ? 1 : 0
  source     = "./modules/lex"
  prefix     = local.prefix
  env_config = local.lex_config
  account_id = local.base_config.account_id
  aws_region = local.base_config.aws_region
}

# ── Bedrock Guardrails (negligible cost at test volume) ───────────────────────
module "guardrails" {
  count      = local.enable_guardrails ? 1 : 0
  source     = "./modules/guardrails"
  prefix     = local.prefix
  env_config = local.guardrails_config
}

# ── Lambda tools (free tier: 1M requests/month) ───────────────────────────────
module "lambda" {
  count                   = local.enable_lambda ? 1 : 0
  source                  = "./modules/lambda"
  prefix                  = local.prefix
  env_config              = local.lambda_config
  ecr_embedding_image_uri = try(one(module.ecr[*].embedding_repository_url), local.ecr_embedding_image_uri)
  reservations_table_name = try(one(module.dynamodb[*].reservations_table_name), "")
  reservations_table_arn  = try(one(module.dynamodb[*].reservations_table_arn), "")
  call_log_table_name     = try(one(module.dynamodb[*].call_log_table_name), "")
  call_log_table_arn      = try(one(module.dynamodb[*].call_log_table_arn), "")
  qdrant_endpoint         = ""  # populated when module "rag" is uncommented
  connect_instance_id     = ""  # populated when module "connect" is uncommented
  connect_domain_id       = ""  # populated when module "connect" is uncommented
}

# ── Observability (CloudWatch free tier covers demo volume) ───────────────────
module "observability" {
  count        = local.enable_observability ? 1 : 0
  source       = "./modules/observability"
  prefix       = local.prefix
  env_config   = local.observability_config
  lambda_names = try(one(module.lambda[*].tool_lambda_names), [])
}

# ── Amazon Connect (per-minute charges — enable when testing calls) ───────────
# module "connect" {
#   count      = local.enable_connect ? 1 : 0
#   source     = "./modules/connect"
#   prefix     = local.prefix
#   env_config = local.connect_config
# }

# ── RAG — EC2 t3.micro always-on (~$8/month) — stop instance when not testing ─
# module "rag" {
#   count      = local.enable_rag ? 1 : 0
#   source     = "./modules/rag"
#   prefix     = local.prefix
#   env_config = local.rag_config
#   vpc_id     = try(one(module.vpc[*].vpc_id), "")
#   subnet_id  = try(one(module.vpc[*].public_subnet_a_id), "")
# }

# ── AgentCore Runtime (compute cost per invocation) ───────────────────────────
# module "agentcore" {
#   count                = local.enable_agentcore ? 1 : 0
#   source               = "./modules/agentcore"
#   prefix               = local.prefix
#   env_config           = local.agentcore_config
#   ecr_agent_image_uri  = try(one(module.ecr[*].agent_repository_url), local.ecr_agent_image_uri)
#   account_id           = local.base_config.account_id
#   aws_region           = local.base_config.aws_region
#   guardrail_id         = try(one(module.guardrails[*].guardrail_id), "")
#   guardrail_version    = try(one(module.guardrails[*].guardrail_version), "1")
#   tool_lambda_arns     = try(one(module.lambda[*].tool_lambda_arns), {})
#   tool_names           = try(one(module.lambda[*].tool_names), [])
#   embedding_lambda_arn = try(one(module.lambda[*].embedding_lambda_arn), "")
# }
