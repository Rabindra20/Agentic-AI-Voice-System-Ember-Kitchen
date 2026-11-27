output "agent_id"           { value = aws_bedrockagent_agent.dineai.agent_id }
output "agent_arn"          { value = aws_bedrockagent_agent.dineai.agent_arn }
output "alias_id"           { value = aws_bedrockagent_agent_alias.live.agent_alias_id }
output "gateway_endpoint" {
  value       = local.gateway_endpoint
  description = "AgentCore Gateway MCP endpoint — injected as AGENTCORE_GATEWAY_ENDPOINT into the agent Lambda"
}
output "agent_lambda_arn" {
  value       = aws_lambda_function.agent.arn
  description = "ARN of the DINEAI agent container Lambda"
}
