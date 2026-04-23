# ── Buckets S3 assets (un par environnement) ────────────────────────────────
resource "aws_s3_bucket" "assets" {
  for_each = local.env_config

  bucket = "${var.project}-${each.key}-assets-${data.aws_caller_identity.current.account_id}"
  tags   = { Name = "${var.project}-${each.key}-assets", Env = each.key }
}

# Versioning activé uniquement en prod
resource "aws_s3_bucket_versioning" "assets" {
  for_each = local.env_config

  bucket = aws_s3_bucket.assets[each.key].id
  versioning_configuration {
    status = each.key == "prod" ? "Enabled" : "Suspended"
  }
}

# Lever le blocage public pour autoriser la politique de lecture
resource "aws_s3_bucket_public_access_block" "assets" {
  for_each = local.env_config

  bucket                  = aws_s3_bucket.assets[each.key].id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Politique : lecture publique pour tous les objets
resource "aws_s3_bucket_policy" "assets_public_read" {
  for_each   = local.env_config
  bucket     = aws_s3_bucket.assets[each.key].id
  depends_on = [aws_s3_bucket_public_access_block.assets]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.assets[each.key].arn}/*"
    }]
  })
}

# CORS pour les uploads depuis le navigateur via Directus
resource "aws_s3_bucket_cors_configuration" "assets" {
  for_each = local.env_config

  bucket = aws_s3_bucket.assets[each.key].id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["https://${local.directus_subdomains[each.key]}"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# Chiffrement AES-256 par défaut
resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  for_each = local.env_config

  bucket = aws_s3_bucket.assets[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
