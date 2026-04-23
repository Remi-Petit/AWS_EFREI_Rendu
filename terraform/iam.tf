# ── ECS Task Execution Role ─────────────────────────────────────────────────
resource "aws_iam_role" "ecs_execution" {
  name = "${var.project}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ── ECS Task Role (permissions pour les containers applicatifs) ─────────────
resource "aws_iam_role" "ecs_task" {
  name = "${var.project}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_s3" {
  name = "${var.project}-ecs-task-s3"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.assets["prod"].arn,
        "${aws_s3_bucket.assets["prod"].arn}/*",
        aws_s3_bucket.assets["test"].arn,
        "${aws_s3_bucket.assets["test"].arn}/*"
      ]
    }]
  })
}

# ── IAM Group : Admins ──────────────────────────────────────────────────────
resource "aws_iam_group" "admins" {
  name = "${var.project}-admins"
}

resource "aws_iam_group_policy_attachment" "admins_full" {
  group      = aws_iam_group.admins.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ── IAM Group : Developers ──────────────────────────────────────────────────
resource "aws_iam_group" "developers" {
  name = "${var.project}-developers"
}

resource "aws_iam_policy" "developer_policy" {
  name        = "${var.project}-developer-policy"
  description = "ECS read + deploy, CloudWatch read"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:Describe*", "ecs:List*", "ecs:UpdateService",
          "ecr:GetAuthorizationToken", "ecr:BatchGetImage",
          "logs:GetLogEvents", "logs:FilterLogEvents",
          "cloudwatch:GetMetricData", "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_group_policy_attachment" "developers" {
  group      = aws_iam_group.developers.name
  policy_arn = aws_iam_policy.developer_policy.arn
}

# ── IAM Group : ReadOnly ─────────────────────────────────────────────────────
resource "aws_iam_group" "readonly" {
  name = "${var.project}-readonly"
}

resource "aws_iam_group_policy_attachment" "readonly" {
  group      = aws_iam_group.readonly.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ── Password Policy ──────────────────────────────────────────────────────────
resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length        = 16
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 5
}
