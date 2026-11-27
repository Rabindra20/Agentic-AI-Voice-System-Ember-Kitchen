output "instance_id"  { value = aws_connect_instance.this.id }
output "instance_arn" { value = aws_connect_instance.this.arn }
output "general_queue_id"   { value = aws_connect_queue.general.queue_id }
output "emergency_queue_id" { value = aws_connect_queue.emergency.queue_id }
output "contact_flow_id"    { value = aws_connect_contact_flow.main.contact_flow_id }
output "cases_domain_id"    { value = "" }
