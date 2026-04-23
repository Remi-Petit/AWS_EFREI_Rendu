variable "project" {
  description = "Nom du projet"
  type        = string
}

variable "env" {
  description = "Environnement (prod, test)"
  type        = string
}

variable "aws_region" {
  description = "Région AWS"
  type        = string
}

variable "vpc_id" {
  description = "ID du VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs des subnets privés"
  type        = list(string)
}

variable "ecs_sg_id" {
  description = "ID du security group ECS"
  type        = string
}

variable "ecs_cluster_id" {
  description = "ID du cluster ECS"
  type        = string
}

variable "https_listener_arn" {
  description = "ARN du listener HTTPS de l'ALB"
  type        = string
}

variable "execution_role_arn" {
  description = "ARN du rôle d'exécution ECS"
  type        = string
}

variable "admin_email" {
  description = "Email administrateur Directus"
  type        = string
  default     = "admin@example.com"
}

variable "cpu" {
  description = "CPU Fargate (units)"
  type        = number
  default     = 512
}

variable "memory" {
  description = "Mémoire Fargate (MB)"
  type        = number
  default     = 1024
}

variable "alb_listener_priority" {
  description = "Priorité de la règle ALB (doit être unique par listener)"
  type        = number
  default     = 110
}

variable "hostname" {
  description = "Nom d'hôte pour la règle ALB (ex: directus.test.aws.remipetit.fr)"
  type        = string
}

variable "s3_bucket" {
  description = "Nom du bucket S3 pour le stockage des fichiers Directus"
  type        = string
}

variable "db_host" {
  description = "Endpoint RDS PostgreSQL"
  type        = string
}

variable "db_name" {
  description = "Nom de la base de données"
  type        = string
}

variable "db_username" {
  description = "Utilisateur RDS"
  type        = string
}

variable "db_password" {
  description = "Mot de passe RDS"
  type        = string
  sensitive   = true
}

variable "task_role_arn" {
  description = "ARN du rôle IAM pour les tâches ECS (accès S3)"
  type        = string
}
