# ── ECR Repositories ─────────────────────────────────────────────────────────
# Un dépôt par environnement — Ansible se charge de builder et pusher les images
resource "aws_ecr_repository" "app" {
  for_each             = toset(var.environments)
  name                 = "${var.project}/${each.value}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Environment = each.value }
}

# ── Lifecycle Policy ──────────────────────────────────────────────────────────
# Garde les 10 dernières images, supprime les plus anciennes
resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = toset(var.environments)
  repository = aws_ecr_repository.app[each.value].name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
