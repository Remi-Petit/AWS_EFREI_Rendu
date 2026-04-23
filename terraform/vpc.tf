# ── VPC par environnement ──────────────────────────────────────────────────
resource "aws_vpc" "main" {
  for_each             = local.env_config
  cidr_block           = each.value.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project}-${each.key}-vpc" }
}

# ── Subnets publics (ALB) ───────────────────────────────────────────────────
resource "aws_subnet" "public" {
  for_each = {
    for pair in flatten([
      for env, _ in local.env_config : [
        for i, az in local.azs : {
          key = "${env}-${i}"
          env = env
          az  = az
          idx = i
        }
      ]
    ]) : pair.key => pair
  }

  vpc_id                  = aws_vpc.main[each.value.env].id
  cidr_block              = cidrsubnet(local.env_config[each.value.env].vpc_cidr, 4, each.value.idx)
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = { Name = "${var.project}-${each.value.env}-public-${each.value.idx}" }
}

# ── Subnets privés (ECS tasks) ──────────────────────────────────────────────
resource "aws_subnet" "private" {
  for_each = {
    for pair in flatten([
      for env, _ in local.env_config : [
        for i, az in local.azs : {
          key = "${env}-${i}"
          env = env
          az  = az
          idx = i
        }
      ]
    ]) : pair.key => pair
  }

  vpc_id            = aws_vpc.main[each.value.env].id
  cidr_block        = cidrsubnet(local.env_config[each.value.env].vpc_cidr, 4, each.value.idx + 3)
  availability_zone = each.value.az

  tags = { Name = "${var.project}-${each.value.env}-private-${each.value.idx}" }
}

# ── Subnets admin (réseau séparé) ───────────────────────────────────────────
resource "aws_subnet" "admin" {
  for_each = {
    for pair in flatten([
      for env, _ in local.env_config : [
        for i, az in local.azs : {
          key = "${env}-${i}"
          env = env
          az  = az
          idx = i
        }
      ]
    ]) : pair.key => pair
  }

  vpc_id            = aws_vpc.main[each.value.env].id
  cidr_block        = cidrsubnet(local.env_config[each.value.env].vpc_cidr, 4, each.value.idx + 6)
  availability_zone = each.value.az

  tags = { Name = "${var.project}-${each.value.env}-admin-${each.value.idx}" }
}

# ── Internet Gateway ─────────────────────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  for_each = local.env_config
  vpc_id   = aws_vpc.main[each.key].id
  tags     = { Name = "${var.project}-${each.key}-igw" }
}

# ── Route table publique ─────────────────────────────────────────────────────
resource "aws_route_table" "public" {
  for_each = local.env_config
  vpc_id   = aws_vpc.main[each.key].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[each.key].id
  }

  tags = { Name = "${var.project}-${each.key}-rt-public" }
}

resource "aws_route_table_association" "public" {
  for_each = {
    for pair in flatten([
      for env, _ in local.env_config : [
        for i, az in local.azs : { key = "${env}-${i}", env = env, idx = i }
      ]
    ]) : pair.key => pair
  }

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public[each.value.env].id
}

# ── NAT Gateway (pour subnets privés) ────────────────────────────────────────
resource "aws_eip" "nat" {
  for_each = local.env_config
  domain   = "vpc"
  tags     = { Name = "${var.project}-${each.key}-nat-eip" }
}

resource "aws_nat_gateway" "main" {
  for_each      = local.env_config
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public["${each.key}-0"].id
  tags          = { Name = "${var.project}-${each.key}-nat" }
  depends_on    = [aws_internet_gateway.main]
}

resource "aws_route_table" "private" {
  for_each = local.env_config
  vpc_id   = aws_vpc.main[each.key].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[each.key].id
  }

  tags = { Name = "${var.project}-${each.key}-rt-private" }
}

resource "aws_route_table_association" "private" {
  for_each = {
    for pair in flatten([
      for env, _ in local.env_config : [
        for i, az in local.azs : { key = "${env}-${i}", env = env, idx = i }
      ]
    ]) : pair.key => pair
  }

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.value.env].id
}
