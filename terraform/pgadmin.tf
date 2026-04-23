module "pgadmin" {
  for_each = local.env_config
  source   = "./modules/pgadmin"

  project            = var.project
  env                = each.key
  aws_region         = var.aws_region
  vpc_id             = aws_vpc.main[each.key].id
  private_subnet_ids = [for k, s in aws_subnet.private : s.id if startswith(k, each.key)]
  ecs_sg_id          = aws_security_group.ecs[each.key].id
  ecs_cluster_id     = aws_ecs_cluster.main[each.key].id
  https_listener_arn = aws_lb_listener.https[each.key].arn
  execution_role_arn = aws_iam_role.ecs_execution.arn
  pgadmin_email      = var.admin_email
}
