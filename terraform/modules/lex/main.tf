data "aws_iam_policy_document" "lex_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lexv2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lex" {
  name               = "${var.prefix}-LexRole"
  assume_role_policy = data.aws_iam_policy_document.lex_assume.json
}

resource "aws_iam_role_policy_attachment" "lex_polly" {
  role       = aws_iam_role.lex.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonPollyFullAccess"
}

resource "aws_lexv2models_bot" "ember" {
  name     = "${var.prefix}-Bot"
  role_arn = aws_iam_role.lex.arn

  data_privacy { child_directed = false }

  idle_session_ttl_in_seconds = var.env_config.idle_session_ttl_in_seconds
  tags                        = { Project = var.prefix }
}

resource "aws_lexv2models_bot_locale" "main" {
  bot_id                           = aws_lexv2models_bot.ember.id
  bot_version                      = "DRAFT"
  locale_id                        = var.env_config.locale_id
  n_lu_intent_confidence_threshold = var.env_config.nlu_confidence_threshold

  voice_settings {
    voice_id = var.env_config.voice_id
    engine   = "neural"
  }
}

locals {
  intents = {
    CheckAvailability = {
      utterances = [
        "Is there availability on Saturday",
        "Do you have any tables free",
        "Can I check if you have space for {PartySize} people",
        "What availability do you have for this weekend",
        "Are you available on {Date}",
        "Check table availability",
      ]
    }
    MakeReservation = {
      utterances = [
        "I'd like to make a reservation",
        "Book a table",
        "Can I reserve a table",
        "I want to book a table for {PartySize} people",
        "Reserve a table for {Date}",
      ]
    }
    ModifyReservation = {
      utterances = [
        "I need to change my reservation",
        "Modify my booking",
        "Can I update my reservation",
        "Change my table booking",
      ]
    }
    CancelReservation = {
      utterances = [
        "Cancel my reservation",
        "I need to cancel my booking",
        "Please cancel my table",
      ]
    }
    DietaryRequirements = {
      utterances = [
        "I have dietary requirements",
        "I'm allergic to {Allergen}",
        "I need a vegan menu",
        "I have a food allergy",
        "Record my dietary needs",
      ]
    }
    CateringEnquiry = {
      utterances = [
        "I'd like a catering quote",
        "How much does catering cost",
        "Tell me about your catering packages",
        "I need catering for an event",
      ]
    }
    PolicyQuestion = {
      utterances = [
        "What is your cancellation policy",
        "Do you have private dining",
        "What are your opening hours",
        "Tell me about your allergy procedures",
        "What events do you host",
      ]
    }
    Escalate = {
      utterances = [
        "I need to speak to someone",
        "Transfer me to a person",
        "I want to speak to a manager",
        "Connect me to staff",
      ]
    }
    EmergencyEscalation = {
      utterances = [
        "This is an emergency",
        "Someone is having an allergic reaction",
        "Medical emergency",
        "I need help urgently",
        "Anaphylaxis",
      ]
    }
  }
}

resource "aws_lexv2models_intent" "intents" {
  for_each = local.intents

  bot_id      = aws_lexv2models_bot.ember.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.main.locale_id
  name        = each.key

  dynamic "sample_utterance" {
    for_each = each.value.utterances
    content { utterance = sample_utterance.value }
  }
}

resource "aws_lexv2models_bot_version" "v1" {
  bot_id = aws_lexv2models_bot.ember.id
  locale_specification = {
    (var.env_config.locale_id) = { source_bot_version = "DRAFT" }
  }
  depends_on = [aws_lexv2models_intent.intents]
}

# aws_lexv2models_bot_alias is not yet available in the hashicorp/aws provider.
# The alias is created via AWS CLI and its ID is stored in SSM for reference.
resource "null_resource" "lex_bot_alias" {
  triggers = {
    bot_id      = aws_lexv2models_bot.ember.id
    bot_version = aws_lexv2models_bot_version.v1.bot_version
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      ALIAS_ID=$(aws lexv2-models list-bot-aliases \
        --bot-id ${aws_lexv2models_bot.ember.id} \
        --region ${var.aws_region} \
        --query "botAliasSummaries[?botAliasName=='${var.prefix}-Live'].botAliasId | [0]" \
        --output text 2>/dev/null)
      if [ -z "$ALIAS_ID" ] || [ "$ALIAS_ID" = "None" ]; then
        ALIAS_ID=$(aws lexv2-models create-bot-alias \
          --bot-id ${aws_lexv2models_bot.ember.id} \
          --bot-alias-name "${var.prefix}-Live" \
          --bot-version ${aws_lexv2models_bot_version.v1.bot_version} \
          --region ${var.aws_region} \
          --query 'botAliasId' \
          --output text)
      fi
      aws ssm put-parameter \
        --name "/${var.prefix}/lex-bot-alias-id" \
        --value "$ALIAS_ID" \
        --type String \
        --overwrite \
        --region ${var.aws_region}
    EOT
  }
}
