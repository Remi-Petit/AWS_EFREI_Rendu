output "alb_dns_names" {
  description = "URLs des load balancers"
  value = {
    for env, alb in aws_lb.main : env => "http://${alb.dns_name}"
  }
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
