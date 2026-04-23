resource "aws_lb" "main" {
  for_each           = local.env_config
  name               = "${var.project}-${each.key}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[each.key].id]
  subnets            = [for k, s in aws_subnet.public : s.id if startswith(k, each.key)]

  tags = { Environment = each.key }
}

resource "aws_lb_target_group" "app" {
  for_each    = local.env_config
  name        = "${var.project}-${each.key}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main[each.key].id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }
}

resource "aws_lb_listener" "http" {
  for_each          = local.env_config
  load_balancer_arn = aws_lb.main[each.key].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ── Listener HTTPS ────────────────────────────────────────────────────────────
resource "aws_lb_listener" "https" {
  for_each          = local.env_config
  load_balancer_arn = aws_lb.main[each.key].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.main.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[each.key].arn
  }
}
