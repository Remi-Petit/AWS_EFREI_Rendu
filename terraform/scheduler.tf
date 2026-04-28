# =============================================================================
# scheduler.tf
# Objectif : Arrêt automatique de l'environnement de TEST à 19h et
#            redémarrage à 8h (lundi-vendredi) via deux Lambdas déclenchées
#            par EventBridge Scheduler.
#            Les Lambdas listent dynamiquement tous les services ECS du cluster
#            test : aucune modification nécessaire lors d'un ajout de service.
# =============================================================================

# ── Account ID (pour les ARNs Lambda permission) ────────────────────────────────
data "aws_caller_identity" "current" {}

# ── Package Lambda (zip généré depuis les sources Python) ─────────────────────
data "archive_file" "stop_test_env" {
  type        = "zip"
  source_file = "${path.module}/lambda/stop_test_env.py"
  output_path = "${path.module}/lambda/stop_test_env.zip"
}

data "archive_file" "start_test_env" {
  type        = "zip"
  source_file = "${path.module}/lambda/start_test_env.py"
  output_path = "${path.module}/lambda/start_test_env.zip"
}

# ── IAM Role pour les Lambdas ─────────────────────────────────────────────────
resource "aws_iam_role" "lambda_scheduler" {
  name = "${var.project}-lambda-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "lambda_scheduler" {
  name        = "${var.project}-lambda-scheduler-policy"
  description = "Permissions Lambda : ECS list/update, RDS stop/start, CloudWatch Logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ecs:ListServices"]
        Resource = aws_ecs_cluster.main["test"].arn
      },
      {
        Effect = "Allow"
        Action = ["ecs:UpdateService"]
        Resource = "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${var.project}-test-cluster/*"
      },
      {
        Effect = "Allow"
        Action = [
          "rds:StopDBInstance", "rds:StartDBInstance",
          "rds:DescribeDBInstances"
        ]
        Resource = aws_db_instance.aurora["test"].arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_scheduler" {
  role       = aws_iam_role.lambda_scheduler.name
  policy_arn = aws_iam_policy.lambda_scheduler.arn
}

# ── IAM Role pour EventBridge Scheduler → Lambda ──────────────────────────────
resource "aws_iam_role" "scheduler" {
  name = "${var.project}-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "scheduler" {
  name        = "${var.project}-scheduler-policy"
  description = "Permet à EventBridge Scheduler d'invoquer les Lambdas"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = [
        aws_lambda_function.stop_test_env.arn,
        aws_lambda_function.start_test_env.arn
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "scheduler" {
  role       = aws_iam_role.scheduler.name
  policy_arn = aws_iam_policy.scheduler.arn
}

# ── Lambda : arrêt de l'environnement de test ─────────────────────────────────
resource "aws_lambda_function" "stop_test_env" {
  function_name    = "${var.project}-stop-test-env"
  description      = "Arrête tous les services ECS et RDS de l'env test"
  filename         = data.archive_file.stop_test_env.output_path
  source_code_hash = data.archive_file.stop_test_env.output_base64sha256
  role             = aws_iam_role.lambda_scheduler.arn
  handler          = "stop_test_env.handler"
  runtime          = "python3.12"
  timeout          = 60

  environment {
    variables = {
      AWS_REGION_NAME = var.aws_region
      ECS_CLUSTER     = aws_ecs_cluster.main["test"].name
      RDS_IDENTIFIER  = "${var.project}-test-postgres"
    }
  }
}

# ── Lambda : démarrage de l'environnement de test ─────────────────────────────
resource "aws_lambda_function" "start_test_env" {
  function_name    = "${var.project}-start-test-env"
  description      = "Démarre RDS puis tous les services ECS de l'env test"
  filename         = data.archive_file.start_test_env.output_path
  source_code_hash = data.archive_file.start_test_env.output_base64sha256
  role             = aws_iam_role.lambda_scheduler.arn
  handler          = "start_test_env.handler"
  runtime          = "python3.12"
  timeout          = 600  # 10 min : attend que RDS soit disponible

  environment {
    variables = {
      AWS_REGION_NAME = var.aws_region
      ECS_CLUSTER     = aws_ecs_cluster.main["test"].name
      RDS_IDENTIFIER  = "${var.project}-test-postgres"
      DESIRED_COUNT   = "1"
    }
  }
}

# ── Permissions Lambda (EventBridge peut invoquer) ────────────────────────────
resource "aws_lambda_permission" "stop_test_env" {
  statement_id  = "AllowEventBridgeScheduler"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stop_test_env.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = "arn:aws:scheduler:${var.aws_region}:${data.aws_caller_identity.current.account_id}:schedule/*/*"
}

resource "aws_lambda_permission" "start_test_env" {
  statement_id  = "AllowEventBridgeScheduler"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_test_env.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = "arn:aws:scheduler:${var.aws_region}:${data.aws_caller_identity.current.account_id}:schedule/*/*"
}

# ── Groupe de schedules ───────────────────────────────────────────────────────
resource "aws_scheduler_schedule_group" "test" {
  name = "${var.project}-test-schedulers"
}

# ── Schedule : arrêt à 19h (lun-ven) ─────────────────────────────────────────
resource "aws_scheduler_schedule" "stop_test" {
  name        = "${var.project}-test-stop"
  group_name  = aws_scheduler_schedule_group.test.name
  description = "Arrêt de l'env test à 19h (lun-ven) via Lambda"

  schedule_expression          = "cron(0 19 ? * MON-FRI *)"
  schedule_expression_timezone = "Europe/Paris"
  state                        = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.stop_test_env.arn
    role_arn = aws_iam_role.scheduler.arn
  }
}

# ── Schedule : démarrage à 8h (lun-ven) ──────────────────────────────────────
resource "aws_scheduler_schedule" "start_test" {
  name        = "${var.project}-test-start"
  group_name  = aws_scheduler_schedule_group.test.name
  description = "Démarrage de l'env test à 8h (lun-ven) via Lambda"

  schedule_expression          = "cron(0 8 ? * MON-FRI *)"
  schedule_expression_timezone = "Europe/Paris"
  state                        = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.start_test_env.arn
    role_arn = aws_iam_role.scheduler.arn
  }
}
