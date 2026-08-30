# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.9/docs/resources/network
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/docs/resources/network.md
resource "libvirt_network" "chr_ether1" {
  name = "${var.prefix}-chr-ether1"
  forward = {
    nat = {
      ports = [
        {
          start = 1024
          end   = 65535
        }
      ]
    }
  }
  ips = [
    {
      address = cidrhost(var.network_cidr, 1)
      netmask = cidrnetmask(var.network_cidr)
      dhcp = {
        ranges = [
          {
            start = cidrhost(var.network_cidr, 2)
            end   = cidrhost(var.network_cidr, -2)
          }
        ]
      }
    }
  ]
}

# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.9/docs/resources/volume
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/docs/resources/volume.md
resource "libvirt_volume" "chr_root" {
  pool     = "default"
  name     = "${var.prefix}-chr-root.img"
  capacity = 16 * 1024 * 1024 * 1024 # GiB.
  target = {
    format = {
      type = "qcow2"
    }
  }
  backing_store = {
    format = {
      type = "qcow2"
    }
    path = "/var/lib/libvirt/images/${var.chr_volume_name}"
  }
}

# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.9/docs/resources/domain
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/docs/resources/domain.md
resource "libvirt_domain" "chr" {
  name        = "${var.prefix}-chr"
  description = "created from ${path.cwd}"
  running     = true
  type        = "kvm"
  vcpu        = 2
  memory      = 1024
  memory_unit = "MiB"
  features = {
    acpi = true
    apic = {}
    pae  = true
  }
  metadata = {
    xml = <<-EOF
        <libosinfo:libosinfo xmlns:libosinfo="http://libosinfo.org/xmlns/libvirt/domain/1.0">
          <libosinfo:os id="http://libosinfo.org/linux/2024"/>
        </libosinfo:libosinfo>
        EOF
  }
  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }
  cpu = {
    mode = "host-passthrough"
  }
  devices = {
    serials = [
      {
        type = "pty"
        target = {
          type = "isa-serial"
        }
      }
    ]
    controllers = [
      {
        type  = "scsi"
        model = "virtio-scsi"
      },
      {
        type = "virtio-serial"
      }
    ]
    channels = [
      {
        source = {
          unix = {
            mode = "bind"
          }
        }
        target = {
          virt_io = {
            name = "org.qemu.guest_agent.0"
          }
        }
      },
    ]
    rngs = [
      {
        model = "virtio"
        backend = {
          random = "/dev/urandom"
        }
      }
    ]
    disks = [
      {
        driver = {
          name = "qemu"
          type = "qcow2"
        }
        source = {
          volume = {
            pool   = libvirt_volume.chr_root.pool
            volume = libvirt_volume.chr_root.name
          }
        }
        target = {
          bus = "scsi"
          dev = "sda"
        }
        wwn = format("000000000000aa%02x", 0)
      },
    ]
    interfaces = [
      {
        type = "network"
        model = {
          type = "virtio"
        }
        mac = {
          address = local.chr_ether1_mac
        }
        source = {
          network = {
            network = libvirt_network.chr_ether1.name
          }
        }
        wait_for_ip = {}
      },
    ]
  }
}

# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.9/docs/data-sources/domain_interface_addresses
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/docs/data-sources/domain_interface_addresses.md
data "libvirt_domain_interface_addresses" "chr" {
  domain = libvirt_domain.chr.name
}
