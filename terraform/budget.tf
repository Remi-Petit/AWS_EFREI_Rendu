# ── Variables budget ──────────────────────────────────────────────────────────
variable "budget_monthly_limit_usd" {
  description = "Limite mensuelle du budget en USD"
  type        = number
  default     = 50
}

variable "budget_alert_threshold_pct" {
  description = "Pourcentage du budget déclenchant l'alerte (ex: 80 = 80%)"
  type        = number
  default     = 80
}

# ── Budget mensuel global ─────────────────────────────────────────────────────
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project}-monthly-cost-budget"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_monthly_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Alerte à X% du budget prévu
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = var.budget_alert_threshold_pct
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.admin_email]
  }

  # Alerte quand le coût réel dépasse 100%
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.admin_email]
  }
}
