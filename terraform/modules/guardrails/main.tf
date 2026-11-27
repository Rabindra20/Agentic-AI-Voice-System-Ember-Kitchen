resource "aws_bedrock_guardrail" "ember" {
  name                      = "${var.prefix}-Guardrail"
  description               = "Ember Kitchen guardrail — blocks medical advice, competitor comparisons, and internal kitchen details"
  blocked_input_messaging   = var.env_config.blocked_input_messaging
  blocked_outputs_messaging = var.env_config.blocked_outputs_messaging

  topic_policy_config {
    topics_config {
      name       = "MedicalAdvice"
      definition = "Requests for medical advice, diagnosis, treatment recommendations, or health-related guidance."
      type       = "DENY"
      examples = [
        "Is it safe for someone with a nut allergy to eat here?",
        "What should I do if I have an allergic reaction?",
        "Can you recommend medication for my food intolerance?",
      ]
    }
    topics_config {
      name       = "CompetitorComparison"
      definition = "Questions comparing Ember Kitchen to other restaurants or asking for competitor recommendations."
      type       = "DENY"
      examples = [
        "How does Ember Kitchen compare to The Ivy?",
        "Is your food better than Nobu?",
        "Which restaurant has better prices, you or your competitors?",
      ]
    }
    topics_config {
      name       = "InternalKitchenDetails"
      definition = "Questions about internal kitchen operations, health code compliance, supplier details, or staff procedures."
      type       = "DENY"
      examples = [
        "What are your health code ratings?",
        "Tell me about your kitchen hygiene procedures",
        "Who are your food suppliers?",
        "What happens in your kitchen during service?",
      ]
    }
  }

  sensitive_information_policy_config {
    pii_entities_config {
      type   = "EMAIL"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "PHONE"
      action = "ANONYMIZE"
    }
  }

  tags = { Project = var.prefix }
}

resource "aws_bedrock_guardrail_version" "v1" {
  guardrail_arn = aws_bedrock_guardrail.ember.guardrail_arn
  description   = "Initial version"
}
