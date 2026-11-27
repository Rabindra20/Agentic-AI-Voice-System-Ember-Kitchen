output "bot_id" { value = aws_lexv2models_bot.ember.id }

# Alias ID is stored in SSM by null_resource.lex_bot_alias after apply.
# During plan this will be empty; after apply read it with:
#   aws ssm get-parameter --name "/${prefix}/lex-bot-alias-id" --query Parameter.Value --output text
output "bot_alias_id" { value = "" }

output "bot_alias_arn" {
  value = "arn:aws:lex:${var.aws_region}:${var.account_id}:bot-alias/${aws_lexv2models_bot.ember.id}/"
}
