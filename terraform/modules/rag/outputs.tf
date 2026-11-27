output "qdrant_instance_id" { value = aws_instance.qdrant.id }
output "qdrant_private_ip"  { value = aws_instance.qdrant.private_ip }
output "qdrant_public_ip"   { value = aws_instance.qdrant.public_ip }
