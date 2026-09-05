# see https://github.com/hashicorp/terraform
terraform {
  required_version = "1.16.0"
  required_providers {
    # see https://developer.hashicorp.com/terraform/language/functions/terraform-encode_tfvars
    terraform = {
      source = "terraform.io/builtin/terraform"
    }
    # see https://registry.terraform.io/providers/hashicorp/local
    # see https://github.com/hashicorp/terraform-provider-local
    local = {
      source  = "hashicorp/local"
      version = "2.9.0"
    }
    # see https://registry.terraform.io/providers/dmacvicar/libvirt
    # see https://github.com/dmacvicar/terraform-provider-libvirt
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.9.9"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

variable "prefix" {
  type    = string
  default = "chr-playground"
}

variable "network_cidr" {
  type    = string
  default = "10.17.7.0/24"
}

variable "chr_version" {
  type = string
}

variable "chr_volume_name" {
  type = string
}

variable "lan_domain" {
  type    = string
  default = "lan.test"
}

# see https://en.wikipedia.org/wiki/MAC_address#Ranges_of_group_and_locally_administered_addresses
locals {
  chr_ether1_mac = format("02:00:00:00:00:%02x", 1)
  chr_ether2_mac = format("02:00:00:00:00:%02x", 2)
}

locals {
  chr_mac = local.chr_ether1_mac
  chr_ip  = data.libvirt_domain_interface_addresses.chr.interfaces[0].addrs[0].addr
  chr_url = "http://${local.chr_ip}"
}

output "chr_mac" {
  value = local.chr_mac
}

output "chr_ip" {
  value = local.chr_ip
}

output "chr_url" {
  value = local.chr_url
}

# see https://registry.terraform.io/providers/hashicorp/local/2.9.0/docs/resources/file
resource "local_file" "output_config" {
  content = provider::terraform::encode_tfvars({
    chr_mac      = local.chr_mac
    chr_ip       = local.chr_ip
    chr_url      = local.chr_url
    chr_username = "admin"
    chr_password = ""
    lan_domain   = var.lan_domain
    debian_mac   = local.debian_mac
    debian_fqdn  = local.debian_fqdn
  })
  filename        = "${path.module}/../config/infra.auto.tfvars"
  file_permission = 0444
}
