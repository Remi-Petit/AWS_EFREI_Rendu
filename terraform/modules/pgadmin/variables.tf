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

variable "pgadmin_email" {
  description = "Email administrateur pgAdmin"
  type        = string
  default     = "admin@example.com"
}

variable "cpu" {
  description = "CPU Fargate (units)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Mémoire Fargate (MB)"
  type        = number
  default     = 512
}
