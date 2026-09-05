# see https://github.com/hashicorp/terraform
terraform {
  required_version = "1.16.0"
  required_providers {
    # see https://registry.terraform.io/providers/terraform-routeros/routeros
    # see https://github.com/terraform-routeros/terraform-provider-routeros
    routeros = {
      source  = "terraform-routeros/routeros"
      version = "1.99.1"
    }
  }
}

provider "routeros" {
  hosturl  = var.chr_url
  username = var.chr_username
  password = var.chr_password
}

variable "chr_mac" {
  type = string
}

variable "chr_ip" {
  type = string
}

variable "chr_url" {
  type = string
}

variable "chr_username" {
  type = string
}

variable "chr_password" {
  type      = string
  sensitive = true
}

variable "dns_servers" {
  type    = list(string)
  default = ["1.1.1.1", "1.0.0.1"] # see https://one.one.one.one
}

variable "lan_ip_cidr" {
  type    = string
  default = "192.168.88.1/24"
}

variable "lan_domain" {
  type = string
}

variable "debian_mac" {
  type = string
}

variable "debian_fqdn" {
  type = string
}

locals {
  lan_gateway_ip       = split("/", var.lan_ip_cidr)[0]
  lan_pool_range_first = 10
  lan_pool_range_last  = 254
  lan_pool_range       = "${cidrhost(var.lan_ip_cidr, local.lan_pool_range_first)}-${cidrhost(var.lan_ip_cidr, local.lan_pool_range_last)}"
  debian_ip            = cidrhost(var.lan_ip_cidr, local.lan_pool_range_first)
}

output "chr_mac" {
  value = var.chr_mac
}

output "chr_ip" {
  value = var.chr_ip
}

output "chr_url" {
  value = var.chr_url
}

# see https://registry.terraform.io/providers/terraform-routeros/routeros/1.99.1/docs/resources/system_identity
resource "routeros_system_identity" "chr" {
  name = "chr"
}

# see https://registry.terraform.io/providers/terraform-routeros/routeros/1.99.1/docs/resources/ip_dns
resource "routeros_ip_dns" "dns_server" {
  allow_remote_requests = true
  servers               = var.dns_servers
}

# see https://registry.terraform.io/providers/terraform-routeros/routeros/1.99.1/docs/resources/interface_list
resource "routeros_interface_list" "wan" {
  name = "WAN"
}

# see https://registry.terraform.io/providers/terraform-routeros/routeros/1.99.1/docs/resources/interface_list
resource "routeros_interface_list" "lan" {
  name = "LAN"
}

# see https://registry.terraform.io/providers/terraform-routeros/routeros/1.99.1/docs/resources/interface_list_member
resource "routeros_interface_list_member" "wan_ether1" {
  list      = routeros_interface_list.wan.name
  interface = "ether1"
}

# see https://registry.terraform.io/providers/terraform-routeros/routeros/1.99.1/docs/resources/interface_list_member
resource "routeros_interface_list_member" "lan_bridge" {
  list      = routeros_interface_list.lan.name
  interface = routeros_interface_bridge.lan.name
}

# see https://registry.terraform.io/providers/terraform-routeros/routeros/1.99.1/docs/resources/interface_bridge
resource "routeros_interface_bridge" "lan" {
  name = "lan"
}

# see https://registry.terraform.io/providers/terraform-routeros/routeros/1.99.1/docs/resources/interface_bridge_port
resource "routeros_interface_bridge_port" "lan_ether2" {
  bridge    = routeros_interface_bridge.lan.name
  interface = "ether2"
  comment   = "debian"
}

# see https://registry.terraform.io/providers/terraform-routeros/routeros/1.99.1/docs/resources/ip_firewall_nat
resource "routeros_ip_firewall_nat" "lan_masquerade" {
  comment            = "lan"
  chain              = "srcnat"
  action             = "masquerade"
  out_interface_list = routeros_interface_list.wan.name
}

# see https://registry.terraform.io/providers/terraform-routeros/routeros/1.99.1/docs/resources/ip_address
resource "routeros_ip_address" "lan" {
  interface = routeros_interface_bridge.lan.name
  address   = var.lan_ip_cidr
}

# see https://registry.terraform.io/providers/terraform-routeros/routeros/1.99.1/docs/resources/ip_pool
resource "routeros_ip_pool" "lan" {
  name   = "lan"
  ranges = [local.lan_pool_range]
}

# see https://registry.terraform.io/providers/terraform-routeros/routeros/1.99.1/docs/resources/ip_dhcp_server
resource "routeros_ip_dhcp_server" "lan" {
  name                      = "lan"
  interface                 = routeros_interface_bridge.lan.name
  address_pool              = routeros_ip_pool.lan.name
  dynamic_lease_identifiers = "client-mac,client-id"
}

# see https://registry.terraform.io/providers/terraform-routeros/routeros/1.99.1/docs/resources/ip_dhcp_server_network
resource "routeros_ip_dhcp_server_network" "lan" {
  address    = cidrsubnet(var.lan_ip_cidr, 0, 0)
  gateway    = local.lan_gateway_ip
  dns_server = [local.lan_gateway_ip]
  domain     = var.lan_domain
}

# see https://registry.terraform.io/providers/terraform-routeros/routeros/1.99.1/docs/resources/ip_dhcp_server_lease
resource "routeros_ip_dhcp_server_lease" "debian" {
  server      = routeros_ip_dhcp_server.lan.name
  mac_address = var.debian_mac
  address     = local.debian_ip
  comment     = var.debian_fqdn
}

# NB this will also create a reverse PTR record (e.g. 10.88.168.192.in-addr.arpa.).
# see https://registry.terraform.io/providers/terraform-routeros/routeros/1.99.1/docs/resources/ip_dns_record
resource "routeros_ip_dns_record" "debian" {
  name    = var.debian_fqdn
  type    = "A"
  address = routeros_ip_dhcp_server_lease.debian.address
}
