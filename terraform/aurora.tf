# ── Mot de passe aléatoire ────────────────────────────────────────────────────
resource "random_password" "aurora" {
  for_each         = local.env_config
  length           = 32
  special          = false
}

# ── SG RDS ────────────────────────────────────────────────────────────────────
resource "aws_security_group" "aurora" {
  for_each    = local.env_config
  name        = "${var.project}-${each.key}-sg-rds"
  description = "Allow PostgreSQL from ECS tasks only"
  vpc_id      = aws_vpc.main[each.key].id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs[each.key].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${each.key}-sg-rds", Environment = each.key }
}

# ── DB Subnet Groups ──────────────────────────────────────────────────────────
resource "aws_db_subnet_group" "aurora" {
  for_each   = local.env_config
  name       = "${var.project}-${each.key}-aurora-subnet-group"
  subnet_ids = [for k, s in aws_subnet.private : s.id if startswith(k, each.key)]

  tags = { Name = "${var.project}-${each.key}-rds-subnet-group", Environment = each.key }
}

# ── Parameter group custom pour désactiver force_ssl en test ─────────────────
resource "aws_db_parameter_group" "test_no_ssl" {
  name        = "${var.project}-test-pg18-no-ssl"
  family      = "postgres18"
  description = "PostgreSQL 18 - SSL non obligatoire pour test"

  parameter {
    name         = "rds.force_ssl"
    value        = "0"
    apply_method = "immediate"
  }
}

# ── RDS PostgreSQL ────────────────────────────────────────────────────────────
# prod : Multi-AZ, db.t3.small — test : Single-AZ, db.t3.micro
resource "aws_db_instance" "aurora" {
  for_each = local.env_config

  identifier        = "${var.project}-${each.key}-postgres"
  engine            = "postgres"
  engine_version    = "18"
  instance_class    = "db.t3.micro"
  allocated_storage = each.key == "prod" ? 20 : 20
  storage_type      = "gp2"
  storage_encrypted = true

  db_name  = replace(var.project, "-", "_")
  username = "dbadmin"
  password = random_password.aurora[each.key].result

  db_subnet_group_name   = aws_db_subnet_group.aurora[each.key].name
  vpc_security_group_ids = [aws_security_group.aurora[each.key].id]
  parameter_group_name   = each.key == "test" ? aws_db_parameter_group.test_no_ssl.name : "default.postgres18"

  multi_az                    = each.key == "prod"
  publicly_accessible         = false
  deletion_protection         = each.key == "prod"
  skip_final_snapshot         = each.key != "prod"
  final_snapshot_identifier   = each.key == "prod" ? "${var.project}-prod-postgres-final" : null
  backup_retention_period     = 1

  tags = { Environment = each.key }
}
