locals {
  directus_subdomains = {
    prod = "directus-app.${var.domain_name}"
    test = "directus-test.${var.domain_name}"
  }
}

module "directus" {
  for_each = local.env_config
  source   = "./modules/directus"

  project            = var.project
  env                = each.key
  aws_region         = var.aws_region
  vpc_id             = aws_vpc.main[each.key].id
  private_subnet_ids = [for k, s in aws_subnet.private : s.id if startswith(k, each.key)]
  ecs_sg_id          = aws_security_group.ecs[each.key].id
  ecs_cluster_id     = aws_ecs_cluster.main[each.key].id
  https_listener_arn = aws_lb_listener.https[each.key].arn
  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn      = aws_iam_role.ecs_task.arn
  admin_email        = var.admin_email
  hostname           = local.directus_subdomains[each.key]
  s3_bucket          = aws_s3_bucket.assets[each.key].bucket
  db_host            = aws_db_instance.aurora[each.key].address
  db_name            = aws_db_instance.aurora[each.key].db_name
  db_username        = aws_db_instance.aurora[each.key].username
  db_password        = random_password.aurora[each.key].result

  # Priorité ALB différente de pgAdmin (100) pour éviter les conflits
  alb_listener_priority = each.key == "prod" ? 110 : 111
}

# ── Enregistrements DNS → ALB pour Directus ───────────────────────────────────
resource "aws_route53_record" "directus" {
  for_each = local.directus_subdomains

  zone_id = aws_route53_zone.main.zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_lb.main[each.key].dns_name
    zone_id                = aws_lb.main[each.key].zone_id
    evaluate_target_health = true
  }
}
