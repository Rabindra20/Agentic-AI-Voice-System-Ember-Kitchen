locals {
  envs_ecr = {
    demo = {
      agent_repository_name     = "agent"
      embedding_repository_name = "embedding"
      image_tag                 = "latest"
      keep_images               = 5
      encryption_type           = "AES256"
    }
  }
  ecr_config = local.envs_ecr[var.env]

  _ecr_base = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"

  # Fallback URIs used when enable_ecr = false (ECR module not deployed).
  # Mirrors lower() in modules/ecr/main.tf naming convention.
  _ecr_agent_fallback_url     = "${local._ecr_base}/${lower("${local.prefix}-${local.ecr_config.agent_repository_name}")}"
  _ecr_embedding_fallback_url = "${local._ecr_base}/${lower("${local.prefix}-${local.ecr_config.embedding_repository_name}")}"

  ecr_agent_image_uri     = "${try(one(module.ecr[*].agent_repository_url), local._ecr_agent_fallback_url)}:${local.ecr_config.image_tag}"
  ecr_embedding_image_uri = "${try(one(module.ecr[*].embedding_repository_url), local._ecr_embedding_fallback_url)}:${local.ecr_config.image_tag}"
}
