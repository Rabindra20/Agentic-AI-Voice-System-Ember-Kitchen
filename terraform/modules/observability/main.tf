resource "aws_sns_topic" "alarms" {
  name = "${var.prefix}-Alarms"
  tags = { Project = var.prefix }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.env_config.alarm_email
}

resource "aws_cloudwatch_log_group" "agent" {
  name              = "/ember-kitchen/${var.prefix}/dineai"
  retention_in_days = var.env_config.log_retention_days
  tags              = { Project = var.prefix }
}

resource "aws_xray_group" "dineai" {
  group_name        = "${var.prefix}-DINEAI"
  filter_expression = "service(\"${var.prefix}-DINEAI\")"
  tags              = { Project = var.prefix }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = toset(var.lambda_names)

  alarm_name          = "${each.key}-Errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Lambda ${each.key} has errors"
  treat_missing_data  = "notBreaching"
  dimensions          = { FunctionName = each.key }
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  tags = { Project = var.prefix }
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${var.prefix}-LambdaHighDuration"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.env_config.lambda_duration_threshold_ms
  alarm_description   = "A Lambda function exceeded ${var.env_config.lambda_duration_threshold_ms}ms duration"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]

  tags = { Project = var.prefix }
}

resource "aws_cloudwatch_log_metric_filter" "token_cost" {
  name           = "${var.prefix}-TokenCost"
  log_group_name = aws_cloudwatch_log_group.agent.name
  pattern        = "[timestamp, requestId, level=\"INFO\", message=\"TOKEN_COST\", input_tokens, output_tokens, cost_usd]"

  metric_transformation {
    name          = "PerCallTokenCostUSD"
    namespace     = "EmberKitchen/DINEAI"
    value         = "$cost_usd"
    default_value = "0"
    unit          = "None"
  }
}

resource "aws_cloudwatch_dashboard" "ember" {
  dashboard_name = "${var.prefix}-Dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          title   = "Per-Call Token Cost (USD)"
          period  = 60
          stat    = "Sum"
          metrics = [["EmberKitchen/DINEAI", "PerCallTokenCostUSD"]]
        }
      },
      {
        type = "metric"
        properties = {
          title   = "Lambda Errors"
          period  = 60
          stat    = "Sum"
          metrics = [for name in var.lambda_names : ["AWS/Lambda", "Errors", "FunctionName", name]]
        }
      }
    ]
  })
}
