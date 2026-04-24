# ── Credentials Directus ──────────────────────────────────────────────────────
resource "random_password" "directus_admin" {
  length  = 24
  special = false
}

resource "random_uuid" "directus_key" {}
resource "random_uuid" "directus_secret" {}

# ── Secrets Manager ───────────────────────────────────────────────────────────
resource "aws_secretsmanager_secret" "directus" {
  name                    = "${var.project}/${var.env}/directus"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "directus" {
  secret_id = aws_secretsmanager_secret.directus.id
  secret_string = jsonencode({
    admin_email    = var.admin_email
    admin_password = random_password.directus_admin.result
    key            = random_uuid.directus_key.result
    secret         = random_uuid.directus_secret.result
    db_password    = var.db_password
  })
}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "directus" {
  name              = "/ecs/${var.project}/${var.env}/directus"
  retention_in_days = 30
}

# ── ALB Target Group ──────────────────────────────────────────────────────────
resource "aws_lb_target_group" "directus" {
  name        = "${var.project}-${var.env}-directus-tg"
  port        = 8055
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/server/health"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }
}

# ── ALB Listener Rule ─────────────────────────────────────────────────────────
resource "aws_lb_listener_rule" "directus" {
  listener_arn = var.https_listener_arn
  priority     = var.alb_listener_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.directus.arn
  }

  condition {
    host_header {
      values = [var.hostname]
    }
  }
}

# ── ECS Task Definition ───────────────────────────────────────────────────────
resource "aws_ecs_task_definition" "directus" {
  family                   = "${var.project}-${var.env}-directus"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([{
    name  = "directus"
    image = "directus/directus:latest"
    portMappings = [{
      containerPort = 8055
      protocol      = "tcp"
    }]
    environment = [
      { name = "PUBLIC_URL",      value = "https://${var.hostname}" },
      { name = "ADMIN_EMAIL",     value = var.admin_email },
      # Base PostgreSQL RDS
      { name = "DB_CLIENT",   value = "pg" },
      { name = "DB_HOST",     value = var.db_host },
      { name = "DB_PORT",     value = "5432" },
      { name = "DB_DATABASE", value = var.db_name },
      { name = "DB_USER",     value = var.db_username },
      # Stockage S3
      { name = "STORAGE_LOCATIONS",         value = "s3" },
      { name = "STORAGE_DEFAULT",           value = "s3" },
      { name = "STORAGE_S3_DRIVER",         value = "s3" },
      { name = "STORAGE_S3_BUCKET",         value = var.s3_bucket },
      { name = "STORAGE_S3_REGION",         value = var.aws_region },
      { name = "STORAGE_S3_PUBLIC_URL",     value = "https://${var.s3_bucket}.s3.${var.aws_region}.amazonaws.com" }
    ]
    secrets = [
      { name = "ADMIN_PASSWORD", valueFrom = "${aws_secretsmanager_secret.directus.arn}:admin_password::" },
      { name = "KEY",            valueFrom = "${aws_secretsmanager_secret.directus.arn}:key::" },
      { name = "SECRET",         valueFrom = "${aws_secretsmanager_secret.directus.arn}:secret::" },
      { name = "DB_PASSWORD",    valueFrom = "${aws_secretsmanager_secret.directus.arn}:db_password::" },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/${var.project}/${var.env}/directus"
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

# ── ECS Service ───────────────────────────────────────────────────────────────
resource "aws_ecs_service" "directus" {
  name            = "${var.project}-${var.env}-directus"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.directus.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.directus.arn
    container_name   = "directus"
    container_port   = 8055
  }

  depends_on = [aws_lb_listener_rule.directus]
}
