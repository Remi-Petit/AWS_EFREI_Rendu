# Note : AWS Client VPN nécessite des certificats TLS.
# Étapes manuelles requises AVANT terraform apply :
#
# 1. Générer les certificats (sur votre machine) :
#    git clone https://github.com/OpenVPN/easy-rsa.git
#    cd easy-rsa/easyrsa3
#    ./easyrsa init-pki
#    ./easyrsa build-ca nopass
#    ./easyrsa build-server-full server nopass
#    ./easyrsa build-client-full client1.domain.tld nopass
#
# 2. Importer dans ACM :
#    aws acm import-certificate #      --certificate fileb://pki/issued/server.crt #      --private-key fileb://pki/private/server.key #      --certificate-chain fileb://pki/ca.crt
#
# 3. Copier les ARNs retournés dans terraform.tfvars :
#    vpn_server_cert_arn = "arn:aws:acm:..."
#    vpn_client_cert_arn = "arn:aws:acm:..."

variable "vpn_server_cert_arn" {
  description = "ARN du certificat serveur VPN (ACM)"
  default     = ""
}

variable "vpn_client_cert_arn" {
  description = "ARN du certificat client VPN (ACM)"
  default     = ""
}

resource "aws_ec2_client_vpn_endpoint" "admin" {
  for_each = {
    for k, v in local.env_config : k => v
    if var.vpn_server_cert_arn != "" && var.vpn_client_cert_arn != ""
  }

  description            = "${var.project}-${each.key}-vpn"
  server_certificate_arn = var.vpn_server_cert_arn
  client_cidr_block      = each.key == "prod" ? "10.200.0.0/22" : "10.200.4.0/22"
  split_tunnel           = true

  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = var.vpn_client_cert_arn
  }

  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.vpn[each.key].name
    cloudwatch_log_stream = "${var.project}-${each.key}-vpn-connections"
  }

  tags = { Name = "${var.project}-${each.key}-vpn", Environment = each.key }
}

resource "aws_cloudwatch_log_group" "vpn" {
  for_each          = local.env_config
  name              = "/vpn/${var.project}/${each.key}"
  retention_in_days = 90
  tags              = { Environment = each.key }
}

resource "aws_ec2_client_vpn_network_association" "admin" {
  for_each = {
    for k, v in local.env_config : k => v
    if var.vpn_server_cert_arn != "" && var.vpn_client_cert_arn != ""
  }

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.admin[each.key].id
  subnet_id              = aws_subnet.admin["${each.key}-0"].id
}
