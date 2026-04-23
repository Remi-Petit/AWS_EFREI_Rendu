resource "aws_secretsmanager_secret" "app" {
  for_each                = local.env_config
  name                    = "${var.project}/${each.key}/app-secrets"
  recovery_window_in_days = 7

  tags = { Environment = each.key }
}

resource "aws_secretsmanager_secret_version" "app" {
  for_each  = local.env_config
  secret_id = aws_secretsmanager_secret.app[each.key].id

  secret_string = jsonencode({
    DB_PASSWORD = "change-me-${each.key}"
    API_KEY     = "change-me-api-key"
  })
}
