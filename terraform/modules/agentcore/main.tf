data "aws_iam_policy_document" "agentcore_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "agentcore" {
  name               = "${var.prefix}-AgentCoreRole"
  assume_role_policy = data.aws_iam_policy_document.agentcore_assume.json
}

resource "aws_iam_role_policy" "agentcore_inline" {
  name = "inline"
  role = aws_iam_role.agentcore.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.env_config.claude_model_id}"
      },
      {
        Effect   = "Allow"
        Action   = ["bedrock:ApplyGuardrail"]
        Resource = "arn:aws:bedrock:${var.aws_region}:${var.account_id}:guardrail/${var.guardrail_id}"
      },
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = values(var.tool_lambda_arns)
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_bedrockagent_agent" "dineai" {
  agent_name                  = "${var.prefix}-DINEAI"
  agent_resource_role_arn     = aws_iam_role.agentcore.arn
  foundation_model            = var.env_config.claude_model_id
  description                 = "DINEAI — Ember Kitchen voice agent"
  idle_session_ttl_in_seconds = var.env_config.idle_session_ttl_in_seconds

  guardrail_configuration {
    guardrail_identifier = var.guardrail_id
    guardrail_version    = var.guardrail_version
  }

  instruction = <<-PROMPT
    You are DINEAI, the AI voice assistant for Ember Kitchen, a premium London restaurant.

    GREETING: Always greet the caller by name on the first turn using the guest_name session attribute.
    If no name is available, ask for it before proceeding.

    TOOLS: Use the provided tools for all reservation and dining operations.
    After any reservation or dietary update, confirm the change by calling verify_booking.
    Always call log_call_outcome at the end of every call.

    VOICE: Speak naturally and concisely. This is a phone call — keep responses under 3 sentences.
    Use Amazon Polly NTTS (Joanna voice) for all speech output.

    ESCALATION:
    - If the caller requests a human agent, call log_call_outcome with intent=Escalate, then transfer.
    - If the caller reports a medical emergency or allergic reaction, immediately call log_call_outcome
      with intent=EmergencyEscalation and transfer to the emergency queue without delay.

    DENIED TOPICS — never discuss:
    1. Medical advice or health recommendations
    2. Comparisons with competitor restaurants
    3. Internal kitchen operations, health codes, or supplier details
    If asked about these topics, politely decline and redirect to dining assistance.

    POLICY QUESTIONS: Use the RAG retrieval tool to answer questions about:
    - General restaurant information, reservation policies, dietary and allergen menu,
      catering packages and pricing, private dining and events, allergy emergency procedures.

    UNVERIFIED CALLERS: If verify_booking returns no reservation, inform the caller and offer to
    create a new booking. Do not modify or cancel reservations for unverified callers.
  PROMPT

  tags = { Project = var.prefix }
}

resource "aws_bedrockagent_agent_alias" "live" {
  agent_id         = aws_bedrockagent_agent.dineai.agent_id
  agent_alias_name = "live"
  description      = "Production alias"
  tags             = { Project = var.prefix }
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "agent_lambda" {
  name               = "${var.prefix}-AgentLambdaRole"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "agent_lambda_inline" {
  name = "inline"
  role = aws_iam_role.agent_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/${var.env_config.claude_model_id}"
      },
      {
        Effect   = "Allow"
        Action   = ["bedrock:ApplyGuardrail"]
        Resource = "arn:aws:bedrock:${var.aws_region}:${var.account_id}:guardrail/${var.guardrail_id}"
      },
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = values(var.tool_lambda_arns)
      },
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = var.embedding_lambda_arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = "*"
      }
    ]
  })
}

locals {
  gateway_endpoint = "https://bedrock-agentcore.${var.aws_region}.amazonaws.com/runtimes/${aws_bedrockagent_agent.dineai.agent_id}/gateway"
  tool_lambda_env_vars = {
    for k, v in var.tool_lambda_arns : "LAMBDA_${k}" => v
  }
}

resource "aws_lambda_function" "agent" {
  function_name = "${var.prefix}-agent"
  role          = aws_iam_role.agent_lambda.arn
  package_type  = "Image"
  image_uri     = var.ecr_agent_image_uri
  timeout       = 30
  memory_size   = 512

  tracing_config { mode = "Active" }

  environment {
    variables = merge(
      {
        AGENTCORE_GATEWAY_ENDPOINT = local.gateway_endpoint
        CLAUDE_MODEL_ID            = var.env_config.claude_model_id
        GUARDRAIL_ID               = var.guardrail_id
        GUARDRAIL_VERSION          = var.guardrail_version
        EMBEDDING_LAMBDA_NAME      = var.embedding_lambda_arn
      },
      local.tool_lambda_env_vars
    )
  }

  tags = { Project = var.prefix }

  depends_on = [aws_bedrockagent_agent.dineai]
}

locals {
  tool_schemas = {
    verify_booking = {
      description = "Verify if a guest has an existing reservation by phone number."
      parameters = {
        guest_phone = { type = "string", description = "Guest phone number", required = true }
      }
    }
    check_table_availability = {
      description = "Check if a table is available for a given date, time, and party size."
      parameters = {
        date       = { type = "string", description = "Date in YYYY-MM-DD format", required = true }
        time       = { type = "string", description = "Time in HH:MM (24h) format", required = true }
        party_size = { type = "integer", description = "Number of guests", required = false }
      }
    }
    book_table = {
      description = "Create a new table reservation."
      parameters = {
        guest_name  = { type = "string", description = "Guest full name", required = true }
        guest_phone = { type = "string", description = "Guest phone number", required = true }
        date        = { type = "string", description = "Date in YYYY-MM-DD format", required = true }
        time        = { type = "string", description = "Time in HH:MM (24h) format", required = true }
        party_size  = { type = "integer", description = "Number of guests", required = true }
      }
    }
    modify_reservation = {
      description = "Modify an existing reservation."
      parameters = {
        reservation_id = { type = "string", description = "Reservation ID to modify", required = true }
        date           = { type = "string", description = "New date in YYYY-MM-DD format", required = false }
        time           = { type = "string", description = "New time in HH:MM (24h) format", required = false }
        party_size     = { type = "integer", description = "New party size", required = false }
      }
    }
    cancel_reservation = {
      description = "Cancel an existing reservation."
      parameters = {
        reservation_id = { type = "string", description = "Reservation ID to cancel", required = true }
      }
    }
    record_dietary_requirements = {
      description = "Record dietary requirements or allergies for a reservation."
      parameters = {
        reservation_id       = { type = "string", description = "Reservation ID", required = true }
        dietary_requirements = { type = "array",  description = "List of dietary requirements or allergens", required = true }
      }
    }
    request_catering_quote = {
      description = "Get a catering quote for an event."
      parameters = {
        package = { type = "string",  description = "Package tier: standard, premium, or luxury", required = false }
        guests  = { type = "integer", description = "Number of guests", required = true }
      }
    }
    log_call_outcome = {
      description = "Log the outcome of a call. Must be called at the end of every interaction."
      parameters = {
        call_id           = { type = "string", description = "Unique call identifier", required = false }
        guest_name        = { type = "string", description = "Guest name", required = false }
        guest_phone       = { type = "string", description = "Guest phone number", required = false }
        intent            = { type = "string", description = "Primary intent of the call", required = true }
        outcome           = { type = "string", description = "Call outcome (completed, escalated, tool_failure, etc.)", required = true }
        escalation_reason = { type = "string", description = "Reason for escalation if applicable", required = false }
      }
    }
  }
}

resource "aws_bedrockagent_agent_action_group" "tools" {
  for_each = toset(var.tool_names)

  agent_id          = aws_bedrockagent_agent.dineai.agent_id
  agent_version     = "DRAFT"
  action_group_name = each.key
  description       = lookup(local.tool_schemas, each.key, { description = each.key }).description

  action_group_executor { lambda = var.tool_lambda_arns[each.key] }

  function_schema {
    member_functions {
      functions {
        name        = each.key
        description = lookup(local.tool_schemas, each.key, { description = each.key }).description

        dynamic "parameters" {
          for_each = lookup(local.tool_schemas, each.key, { parameters = {} }).parameters
          content {
            map_block_key = parameters.key
            type          = parameters.value.type
            description   = parameters.value.description
            required      = parameters.value.required
          }
        }
      }
    }
  }

  depends_on = [aws_bedrockagent_agent.dineai]
}
