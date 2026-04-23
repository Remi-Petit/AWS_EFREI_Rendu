resource "aws_wafv2_web_acl" "main" {
  name        = "waf-main"
  description = "WAF principal - regles communes"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # Regle 1 : AWS Managed Rules Common
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        # Exclure la limite de taille sur le body pour les uploads Directus (/files)
        rule_action_override {
          name = "SizeRestrictions_BODY"
          action_to_use {
            count {}
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # Regle 2 : Bot Control
  rule {
    name     = "AWSManagedRulesBotControlRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesBotControlRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BotControlMetric"
      sampled_requests_enabled   = true
    }
  }

  # Regle 3 : Rate Limiting
  rule {
    name     = "RateLimitRule"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitMetric"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "WAFMainMetric"
    sampled_requests_enabled   = true
  }

  tags = {
    Name        = "waf-main"
    Environment = "all"
  }
}

# Association WAF -> ALB Prod
resource "aws_wafv2_web_acl_association" "prod" {
  resource_arn = aws_lb.main["prod"].arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

# Association WAF -> ALB Test
resource "aws_wafv2_web_acl_association" "test" {
  resource_arn = aws_lb.main["test"].arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}
