resource "aws_ecr_repository" "agent" {
  name                 = lower("${var.prefix}-${var.env_config.agent_repository_name}")
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = var.env_config.encryption_type
  }

  image_scanning_configuration { scan_on_push = true }
  tags = { Project = var.prefix }
}

resource "aws_ecr_lifecycle_policy" "agent" {
  repository = aws_ecr_repository.agent.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last ${var.env_config.keep_images} images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = var.env_config.keep_images }
      action       = { type = "expire" }
    }]
  })
}

# Embedding model runs as a self-hosted Lambda container image (sentence-transformers).
# Amazon Titan Embeddings is prohibited — the model must be open-source and container-based.
resource "aws_ecr_repository" "embedding" {
  name                 = lower("${var.prefix}-${var.env_config.embedding_repository_name}")
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = var.env_config.encryption_type
  }

  image_scanning_configuration { scan_on_push = true }
  tags = { Project = var.prefix }
}

resource "aws_ecr_lifecycle_policy" "embedding" {
  repository = aws_ecr_repository.embedding.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last ${var.env_config.keep_images} images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = var.env_config.keep_images }
      action       = { type = "expire" }
    }]
  })
}
