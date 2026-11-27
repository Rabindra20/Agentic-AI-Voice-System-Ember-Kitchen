data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.prefix}-LambdaRole"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "lambda_inline" {
  name = "inline"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem",
          "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:Scan"]
        Resource = [var.reservations_table_arn, "${var.reservations_table_arn}/index/*",
        var.call_log_table_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["connect:CreateCase", "cases:CreateCase", "cases:GetCase", "connect:GetCase"]
        Resource = "*"
      }
    ]
  })
}

data "archive_file" "tools" {
  type        = "zip"
  output_path = "${path.module}/tools.zip"
  source {
    content  = file("${path.module}/src/tools.py")
    filename = "tools.py"
  }
}

locals {
  tool_names = [
    "verify_booking",
    "check_table_availability",
    "book_table",
    "modify_reservation",
    "cancel_reservation",
    "record_dietary_requirements",
    "request_catering_quote",
    "log_call_outcome",
  ]
}

resource "aws_lambda_function" "tools" {
  for_each = toset(local.tool_names)

  function_name    = "${var.prefix}-${each.key}"
  role             = aws_iam_role.lambda.arn
  handler          = "tools.${each.key}"
  runtime          = var.env_config.runtime
  filename         = data.archive_file.tools.output_path
  source_code_hash = data.archive_file.tools.output_base64sha256
  timeout          = var.env_config.timeout
  memory_size      = var.env_config.memory_size

  tracing_config { mode = "Active" }

  environment {
    variables = {
      RESERVATIONS_TABLE   = var.reservations_table_name
      CALL_LOG_TABLE       = var.call_log_table_name
      QDRANT_ENDPOINT      = var.qdrant_endpoint
      CONNECT_INSTANCE_ID  = var.connect_instance_id
      CONNECT_DOMAIN_ID    = var.connect_domain_id
    }
  }

  tags = { Project = var.prefix }
}

# Embedding model is self-hosted (BAAI/bge-small-en-v1.5 via sentence-transformers).
# Runs as a Lambda container image — Amazon Titan Embeddings is prohibited.
resource "aws_lambda_function" "embedding" {
  function_name = "${var.prefix}-embedding"
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = var.ecr_embedding_image_uri
  timeout       = var.env_config.embedding.timeout
  memory_size   = var.env_config.embedding.memory_size

  tracing_config { mode = "Active" }

  environment {
    variables = {
      QDRANT_ENDPOINT   = var.qdrant_endpoint
      QDRANT_COLLECTION = "ember_kitchen_policies"
    }
  }

  tags = { Project = var.prefix }
}
