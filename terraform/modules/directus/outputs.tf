output "target_group_arn" {
  description = "ARN du target group Directus"
  value       = aws_lb_target_group.directus.arn
}

output "secret_arn" {
  description = "ARN du secret Directus dans Secrets Manager"
  value       = aws_secretsmanager_secret.directus.arn
}

output "service_name" {
  description = "Nom du service ECS Directus"
  value       = aws_ecs_service.directus.name
}
