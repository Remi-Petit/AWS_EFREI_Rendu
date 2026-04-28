# ── CloudWatch Log Groups ────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "ecs" {
  for_each          = local.env_config
  name              = "/ecs/${var.project}/${each.key}"
  retention_in_days = 30
  tags              = { Environment = each.key }
}

# ── ECS Clusters ─────────────────────────────────────────────────────────────
resource "aws_ecs_cluster" "main" {
  for_each = local.env_config
  name     = "${var.project}-${each.key}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Environment = each.key }
}

# ── Task Definitions ──────────────────────────────────────────────────────────
resource "aws_ecs_task_definition" "app" {
  for_each                 = local.env_config
  family                   = "${var.project}-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task[each.key].arn

  container_definitions = jsonencode([{
    name  = "app"
    image = "${aws_ecr_repository.app[each.key].repository_url}:latest"
    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/${var.project}/${each.key}"
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])

  # Ansible gère les mises à jour d'image — Terraform ne doit pas écraser les déploiements
  lifecycle {
    ignore_changes = [container_definitions]
  }
}

# ── ECS Services ─────────────────────────────────────────────────────────────
resource "aws_ecs_service" "app" {
  for_each        = local.env_config
  name            = "${var.project}-${each.key}-service"
  cluster         = aws_ecs_cluster.main[each.key].id
  task_definition = aws_ecs_task_definition.app[each.key].arn
  desired_count   = each.value.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [for k, s in aws_subnet.private : s.id if startswith(k, each.key)]
    security_groups = [aws_security_group.ecs[each.key].id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app[each.key].arn
    container_name   = "app"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.http]

  # Ansible met à jour la task_definition — Terraform ne doit pas régresser la version
  lifecycle {
    ignore_changes = [task_definition]
  }
}
