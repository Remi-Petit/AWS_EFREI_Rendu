output "target_group_arn" {
  description = "ARN du target group pgAdmin"
  value       = aws_lb_target_group.pgadmin.arn
}

output "secret_arn" {
  description = "ARN du secret pgAdmin dans Secrets Manager"
  value       = aws_secretsmanager_secret.pgadmin.arn
}

output "service_name" {
  description = "Nom du service ECS pgAdmin"
  value       = aws_ecs_service.pgadmin.name
}
