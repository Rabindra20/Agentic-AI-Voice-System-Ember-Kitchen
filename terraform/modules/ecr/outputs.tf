output "agent_repository_url"     { value = aws_ecr_repository.agent.repository_url }
output "agent_repository_name"    { value = aws_ecr_repository.agent.name }
output "embedding_repository_url" { value = aws_ecr_repository.embedding.repository_url }
output "embedding_repository_name" { value = aws_ecr_repository.embedding.name }
