output "vpc_id" {
  value = try(one(module.vpc[*].vpc_id), null)
}

output "public_subnet_ids" {
  value = try(one(module.vpc[*].public_subnet_ids), null)
}

output "private_subnet_ids" {
  value = try(one(module.vpc[*].private_subnet_ids), null)
}

output "ecr_agent_repository_url" {
  value       = try(one(module.ecr[*].agent_repository_url), null)
  description = "ECR URL for the DINEAI agent image (AgentCore Runtime)"
}

output "ecr_embedding_repository_url" {
  value       = try(one(module.ecr[*].embedding_repository_url), null)
  description = "ECR URL for the self-hosted embedding image (sentence-transformers container Lambda)"
}

output "reservations_table_name" {
  value = try(one(module.dynamodb[*].reservations_table_name), null)
}

output "lex_bot_id" {
  value = try(one(module.lex[*].bot_id), null)
}

output "lex_bot_alias_id" {
  value = try(one(module.lex[*].bot_alias_id), null)
}

output "guardrail_id" {
  value = try(one(module.guardrails[*].guardrail_id), null)
}

output "alarm_topic_arn" {
  value = try(one(module.observability[*].alarm_topic_arn), null)
}

# ── Enabled when cost-incurring modules are uncommented in main.tf ────────────

# output "connect_instance_id" {
#   value = try(one(module.connect[*].instance_id), null)
# }

# output "connect_instance_arn" {
#   value = try(one(module.connect[*].instance_arn), null)
# }

# output "qdrant_instance_id" {
#   value = try(one(module.rag[*].qdrant_instance_id), null)
# }

# output "qdrant_private_ip" {
#   value = try(one(module.rag[*].qdrant_private_ip), null)
# }

# output "agentcore_agent_id" {
#   value = try(one(module.agentcore[*].agent_id), null)
# }

# output "agentcore_gateway_endpoint" {
#   value       = try(one(module.agentcore[*].gateway_endpoint), null)
#   description = "AgentCore Gateway MCP endpoint"
# }

# output "agentcore_agent_lambda_arn" {
#   value       = try(one(module.agentcore[*].agent_lambda_arn), null)
#   description = "DINEAI agent container Lambda ARN"
# }
