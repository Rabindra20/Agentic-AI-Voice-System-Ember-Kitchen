output "reservations_table_name" { value = aws_dynamodb_table.reservations.name }
output "reservations_table_arn"  { value = aws_dynamodb_table.reservations.arn }
output "call_log_table_name"     { value = aws_dynamodb_table.call_log.name }
output "call_log_table_arn"      { value = aws_dynamodb_table.call_log.arn }
