output "alb_dns_names" {
  description = "URLs des load balancers"
  value = {
    for env, alb in aws_lb.main : env => "http://${alb.dns_name}"
  }
}

output "custom_domain_urls" {
  description = "URLs publiques avec nom de domaine"
  value = {
    for env, sub in local.env_subdomains : env => "https://${sub}.${var.domain_name}"
  }
}

output "route53_name_servers" {
  description = "NS à configurer chez votre registrar pour déléguer aws.remipetit.fr vers Route 53"
  value       = aws_route53_zone.main.name_servers
}

output "ecs_cluster_names" {
  description = "Noms des clusters ECS"
  value = {
    for env, cluster in aws_ecs_cluster.main : env => cluster.name
  }
}

output "cloudwatch_dashboards" {
  description = "Liens vers les dashboards CloudWatch"
  value = {
    for env, _ in local.env_config :
    env => "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${var.project}-${env}"
  }
}

output "secrets_arns" {
  description = "ARNs des secrets"
  value = {
    for env, s in aws_secretsmanager_secret.app : env => s.arn
  }
}

output "ecr_repository_urls" {
  description = "URLs des dépôts ECR (utilisées par Ansible pour builder et pusher les images)"
  value = {
    for env, repo in aws_ecr_repository.app : env => repo.repository_url
  }
}

output "ecs_service_names" {
  description = "Noms des services ECS (utilisés par Ansible pour forcer les déploiements)"
  value = {
    for env, svc in aws_ecs_service.app : env => svc.name
  }
}

output "aurora_endpoints" {
  description = "Endpoints des instances RDS PostgreSQL"
  value = {
    for env, db in aws_db_instance.aurora : env => db.address
  }
}

output "aurora_reader_endpoints" {
  description = "Endpoints reader RDS (Multi-AZ prod uniquement)"
  value = {
    for env, db in aws_db_instance.aurora : env => db.address
  }
}

output "aurora_database_name" {
  description = "Nom de la base de données"
  value       = replace(var.project, "-", "_")
}

output "aurora_master_username" {
  description = "Utilisateur maître RDS"
  value       = "dbadmin"
}
