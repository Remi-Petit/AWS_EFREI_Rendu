variable "aws_region" {
  default = "eu-west-3"
}

variable "project" {
  default = "myapp"
}

variable "environments" {
  default = ["prod", "test"]
}

variable "vpn_client_cidr" {
  default = "10.200.0.0/16"
}

variable "admin_email" {
  default = "admin@example.com"
}
