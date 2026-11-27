resource "aws_connect_instance" "this" {
  identity_management_type = "CONNECT_MANAGED"
  inbound_calls_enabled    = var.env_config.inbound_calls_enabled
  outbound_calls_enabled   = var.env_config.outbound_calls_enabled
  instance_alias           = var.env_config.instance_alias

  tags = { Project = var.prefix }
}

resource "aws_connect_hours_of_operation" "business" {
  instance_id = aws_connect_instance.this.id
  name        = "${var.prefix}-BusinessHours"
  description = "Tue-Sun 10:00-22:00; closed Monday"
  time_zone   = "Europe/London"

  # Monday is intentionally omitted — Ember Kitchen is closed on Mondays.
  config {
    day = "TUESDAY"
    start_time {
      hours   = 10
      minutes = 0
    }
    end_time {
      hours   = 22
      minutes = 0
    }
  }
  config {
    day = "WEDNESDAY"
    start_time {
      hours   = 10
      minutes = 0
    }
    end_time {
      hours   = 22
      minutes = 0
    }
  }
  config {
    day = "THURSDAY"
    start_time {
      hours   = 10
      minutes = 0
    }
    end_time {
      hours   = 22
      minutes = 0
    }
  }
  config {
    day = "FRIDAY"
    start_time {
      hours   = 10
      minutes = 0
    }
    end_time {
      hours   = 22
      minutes = 0
    }
  }
  config {
    day = "SATURDAY"
    start_time {
      hours   = 10
      minutes = 0
    }
    end_time {
      hours   = 22
      minutes = 0
    }
  }
  config {
    day = "SUNDAY"
    start_time {
      hours   = 10
      minutes = 0
    }
    end_time {
      hours   = 22
      minutes = 0
    }
  }

  tags = { Project = var.prefix }
}

resource "aws_connect_queue" "general" {
  instance_id           = aws_connect_instance.this.id
  name                  = "${var.prefix}-GeneralQueue"
  hours_of_operation_id = aws_connect_hours_of_operation.business.hours_of_operation_id
  description           = "General guest enquiries"
  max_contacts          = var.env_config.general_queue_max

  tags = { Project = var.prefix }
}

resource "aws_connect_queue" "emergency" {
  instance_id           = aws_connect_instance.this.id
  name                  = "${var.prefix}-EmergencyQueue"
  hours_of_operation_id = aws_connect_hours_of_operation.business.hours_of_operation_id
  description           = "Emergency escalation queue"
  max_contacts          = var.env_config.emergency_queue_max

  tags = { Project = var.prefix }
}

resource "aws_connect_routing_profile" "general" {
  instance_id               = aws_connect_instance.this.id
  name                      = "${var.prefix}-GeneralRouting"
  description               = "General routing profile"
  default_outbound_queue_id = aws_connect_queue.general.queue_id

  media_concurrencies {
    channel     = "VOICE"
    concurrency = 1
  }

  queue_configs {
    channel  = "VOICE"
    delay    = 0
    priority = 1
    queue_id = aws_connect_queue.general.queue_id
  }

  tags = { Project = var.prefix }
}

resource "aws_connect_contact_flow" "main" {
  instance_id = aws_connect_instance.this.id
  name        = "${var.prefix}-MainFlow"
  description = "Main IVR: hours check → Lex NLU → agent routing"
  type        = "CONTACT_FLOW"

  content = jsonencode({
    Version     = "2019-10-30"
    StartAction = "check-hours"
    Actions = [
      {
        Identifier = "check-hours"
        Type       = "CheckHoursOfOperation"
        Parameters = { HoursOfOperationId = aws_connect_hours_of_operation.business.hours_of_operation_id }
        Transitions = {
          NextAction = "lex-interaction"
          Errors     = [{ NextAction = "off-hours", ErrorType = "NoMatchingError" }]
          Conditions = [{ NextAction = "off-hours", Condition = { Operator = "Equals", Operands = ["False"] } }]
        }
      },
      {
        Identifier = "off-hours"
        Type       = "MessageParticipant"
        Parameters = {
          Text             = "Thank you for calling Ember Kitchen. We are currently closed. We are open Tuesday to Sunday, 10am to 10pm, and closed on Mondays. Please call back during those hours or visit our website. Goodbye."
          TextToSpeechType = "text"
        }
        Transitions = { NextAction = "disconnect" }
      },
      {
        Identifier = "lex-interaction"
        Type       = "ConnectParticipantWithLexBot"
        Parameters = { LexV2Bot = { AliasArn = "PLACEHOLDER_LEX_ALIAS_ARN" } }
        Transitions = {
          NextAction = "route-general"
          Conditions = [
            { NextAction = "route-general",   Condition = { Operator = "Equals", Operands = ["Complete"] } },
            { NextAction = "route-general",   Condition = { Operator = "Equals", Operands = ["Escalate"] } },
            { NextAction = "route-emergency", Condition = { Operator = "Equals", Operands = ["EscalateEmergency"] } }
          ]
          Errors = [{ NextAction = "route-general", ErrorType = "NoMatchingError" }]
        }
      },
      {
        Identifier  = "route-general"
        Type        = "TransferContactToQueue"
        Parameters  = { QueueId = aws_connect_queue.general.queue_id }
        Transitions = { NextAction = "disconnect", Errors = [{ NextAction = "disconnect", ErrorType = "NoMatchingError" }] }
      },
      {
        Identifier  = "route-emergency"
        Type        = "TransferContactToQueue"
        Parameters  = { QueueId = aws_connect_queue.emergency.queue_id }
        Transitions = { NextAction = "disconnect", Errors = [{ NextAction = "disconnect", ErrorType = "NoMatchingError" }] }
      },
      {
        Identifier  = "disconnect"
        Type        = "DisconnectParticipant"
        Parameters  = {}
        Transitions = {}
      }
    ]
  })

  tags = { Project = var.prefix }
}
