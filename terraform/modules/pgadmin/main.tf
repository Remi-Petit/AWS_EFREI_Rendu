# ── Mot de passe aléatoire pour pgAdmin ──────────────────────────────────────
resource "random_password" "pgadmin" {
  length  = 24
  special = false
}

# ── Secret Manager ─────────────────────────────────────────────────────────
resource "aws_secretsmanager_secret" "pgadmin" {
  name                    = "${var.project}/${var.env}/pgadmin"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "pgadmin" {
  secret_id = aws_secretsmanager_secret.pgadmin.id
  secret_string = jsonencode({
    email    = var.pgadmin_email
    password = random_password.pgadmin.result
  })
}

# ── EFS pour la persistance pgAdmin (/var/lib/pgadmin) ───────────────────────
resource "aws_security_group" "efs_pgadmin" {
  name        = "${var.project}-${var.env}-sg-efs-pgadmin"
  description = "Allow NFS from ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [var.ecs_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${var.env}-sg-efs-pgadmin" }
}

resource "aws_efs_file_system" "pgadmin" {
  encrypted = true
  tags      = { Name = "${var.project}-${var.env}-pgadmin-efs" }
}

resource "aws_efs_mount_target" "pgadmin" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.pgadmin.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs_pgadmin.id]
}

resource "aws_efs_access_point" "pgadmin" {
  file_system_id = aws_efs_file_system.pgadmin.id

  posix_user {
    gid = 5050
    uid = 5050
  }

  root_directory {
    path = "/pgadmin"
    creation_info {
      owner_gid   = 5050
      owner_uid   = 5050
      permissions = "755"
    }
  }

  tags = { Name = "${var.project}-${var.env}-pgadmin-ap" }
}

# ── CloudWatch Log Group ───────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "pgadmin" {
  name              = "/ecs/${var.project}/${var.env}/pgadmin"
  retention_in_days = 30
}

# ── ALB Target Group ───────────────────────────────────────────────────────
resource "aws_lb_target_group" "pgadmin" {
  name        = "${var.project}-${var.env}-pgadmin-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/pgadmin/misc/ping"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }
}

# ── ALB Listener Rule ──────────────────────────────────────────────────────
resource "aws_lb_listener_rule" "pgadmin" {
  listener_arn = var.https_listener_arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.pgadmin.arn
  }

  condition {
    path_pattern {
      values = ["/pgadmin", "/pgadmin/*"]
    }
  }
}

# ── ECS Task Definition ────────────────────────────────────────────────────
resource "aws_ecs_task_definition" "pgadmin" {
  family                   = "${var.project}-${var.env}-pgadmin"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn

  volume {
    name = "pgadmin-data"
    efs_volume_configuration {
      file_system_id          = aws_efs_file_system.pgadmin.id
      transit_encryption      = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.pgadmin.id
        iam             = "DISABLED"
      }
    }
  }

  container_definitions = jsonencode([{
    name  = "pgadmin"
    image = "dpage/pgadmin4:latest"
    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
    }]
    environment = [
      { name = "PGADMIN_DEFAULT_EMAIL",    value = var.pgadmin_email },
      { name = "PGADMIN_DEFAULT_PASSWORD", value = random_password.pgadmin.result },
      { name = "PGADMIN_LISTEN_PORT",      value = "80" },
      { name = "SCRIPT_NAME",              value = "/pgadmin" }
    ]
    mountPoints = [{
      sourceVolume  = "pgadmin-data"
      containerPath = "/var/lib/pgadmin"
      readOnly      = false
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/${var.project}/${var.env}/pgadmin"
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])

  depends_on = [aws_efs_mount_target.pgadmin]
}

# ── ECS Service ────────────────────────────────────────────────────────────
resource "aws_ecs_service" "pgadmin" {
  name            = "${var.project}-${var.env}-pgadmin"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.pgadmin.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.pgadmin.arn
    container_name   = "pgadmin"
    container_port   = 80
  }

  depends_on = [aws_lb_listener_rule.pgadmin]
}
