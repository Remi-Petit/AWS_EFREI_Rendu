# ── SG ALB ─────────────────────────────────────────────────────────────────
resource "aws_security_group" "alb" {
  for_each    = local.env_config
  name        = "${var.project}-${each.key}-sg-alb"
  description = "Allow HTTP/HTTPS from internet"
  vpc_id      = aws_vpc.main[each.key].id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${each.key}-sg-alb" }
}

# ── SG ECS tasks ────────────────────────────────────────────────────────────
resource "aws_security_group" "ecs" {
  for_each    = local.env_config
  name        = "${var.project}-${each.key}-sg-ecs"
  description = "Allow traffic from ALB only"
  vpc_id      = aws_vpc.main[each.key].id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb[each.key].id]
  }
  # Port 8055 requis pour Directus
  ingress {
    from_port       = 8055
    to_port         = 8055
    protocol        = "tcp"
    security_groups = [aws_security_group.alb[each.key].id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${each.key}-sg-ecs" }
}

# ── SG Admin ────────────────────────────────────────────────────────────────
resource "aws_security_group" "admin" {
  for_each    = local.env_config
  name        = "${var.project}-${each.key}-sg-admin"
  description = "Admin access via VPN only"
  vpc_id      = aws_vpc.main[each.key].id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpn_client_cidr]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpn_client_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${each.key}-sg-admin" }
}
