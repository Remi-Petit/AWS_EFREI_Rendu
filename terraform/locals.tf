locals {
  azs = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]

  env_subdomains = {
    prod = "app"
    test = "test"
  }

  env_config = {
    prod = {
      vpc_cidr       = "10.0.0.0/16"
      desired_count  = 3
      cpu            = 512
      memory         = 1024
      min_capacity   = 3
      max_capacity   = 10
    }
    test = {
      vpc_cidr       = "10.1.0.0/16"
      desired_count  = 1
      cpu            = 256
      memory         = 512
      min_capacity   = 1
      max_capacity   = 3
    }
  }
}
