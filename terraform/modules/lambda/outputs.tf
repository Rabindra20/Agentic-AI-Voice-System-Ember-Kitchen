output "lambda_role_arn" {
  value = aws_iam_role.lambda.arn
}

output "tool_lambda_arns" {
  value = { for k, v in aws_lambda_function.tools : k => v.arn }
}

output "tool_names" {
  value = local.tool_names
}

output "tool_lambda_names" {
  value = [for v in aws_lambda_function.tools : v.function_name]
}

output "embedding_lambda_arn" {
  value = aws_lambda_function.embedding.arn
}
