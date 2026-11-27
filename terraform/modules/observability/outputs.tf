output "alarm_topic_arn"   { value = aws_sns_topic.alarms.arn }
output "log_group_name"    { value = aws_cloudwatch_log_group.agent.name }
output "xray_group_arn"    { value = aws_xray_group.dineai.arn }
