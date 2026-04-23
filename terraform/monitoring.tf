# ── SNS Topic pour les alertes ───────────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  for_each = local.env_config
  name     = "${var.project}-${each.key}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = local.env_config
  topic_arn = aws_sns_topic.alerts[each.key].arn
  protocol  = "email"
  endpoint  = var.admin_email
}

# ── Alarme CPU élevé ──────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each            = local.env_config
  alarm_name          = "${var.project}-${each.key}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU > 80% sur ${each.key}"
  alarm_actions       = [aws_sns_topic.alerts[each.key].arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.main[each.key].name
    ServiceName = aws_ecs_service.app[each.key].name
  }
}

# ── Alarme erreurs 5xx ALB ───────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  for_each            = local.env_config
  alarm_name          = "${var.project}-${each.key}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Trop d erreurs 5xx sur ${each.key}"
  alarm_actions       = [aws_sns_topic.alerts[each.key].arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main[each.key].arn_suffix
  }
}

# ── Alarme latence ALB ───────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  for_each            = local.env_config
  alarm_name          = "${var.project}-${each.key}-alb-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Latence > 1s sur ${each.key}"
  alarm_actions       = [aws_sns_topic.alerts[each.key].arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main[each.key].arn_suffix
  }
}

# ── Dashboard CloudWatch ─────────────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "main" {
  for_each       = local.env_config
  dashboard_name = "${var.project}-${each.key}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "ECS CPU Utilization"
          region  = var.aws_region
          period  = 60
          stat    = "Average"
          view    = "timeSeries"
          stacked = false
          metrics = [["AWS/ECS", "CPUUtilization",
            "ClusterName", aws_ecs_cluster.main[each.key].name,
            "ServiceName", aws_ecs_service.app[each.key].name]]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "ECS Memory Utilization"
          region  = var.aws_region
          period  = 60
          stat    = "Average"
          view    = "timeSeries"
          stacked = false
          metrics = [["AWS/ECS", "MemoryUtilization",
            "ClusterName", aws_ecs_cluster.main[each.key].name,
            "ServiceName", aws_ecs_service.app[each.key].name]]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 8
        height = 6
        properties = {
          title   = "ALB Request Count"
          region  = var.aws_region
          period  = 60
          stat    = "Sum"
          view    = "timeSeries"
          stacked = false
          metrics = [["AWS/ApplicationELB", "RequestCount",
            "LoadBalancer", aws_lb.main[each.key].arn_suffix]]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 6
        width  = 8
        height = 6
        properties = {
          title   = "ALB 5XX Errors"
          region  = var.aws_region
          period  = 60
          stat    = "Sum"
          view    = "timeSeries"
          stacked = false
          metrics = [["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count",
            "LoadBalancer", aws_lb.main[each.key].arn_suffix]]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 6
        width  = 8
        height = 6
        properties = {
          title   = "ALB Response Time"
          region  = var.aws_region
          period  = 60
          stat    = "Average"
          view    = "timeSeries"
          stacked = false
          metrics = [["AWS/ApplicationELB", "TargetResponseTime",
            "LoadBalancer", aws_lb.main[each.key].arn_suffix]]
        }
      }
    ]
  })
}
