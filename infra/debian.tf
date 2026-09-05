# NB this uses the vagrant debian image imported from https://github.com/rgl/debian-vagrant.
variable "debian_volume_name" {
  type    = string
  default = "debian-13-uefi-amd64_vagrant_box_image_0.0.0_box_0.img"
}

# see https://gitlab.com/libosinfo/osinfo-db/-/tree/main/data/os/debian.org/debian-13.xml.in
locals {
  debian_os_id = "http://debian.org/debian/${regex("debian-([^-]+)", var.debian_volume_name)[0]}"
}

# create a cloud-init cloud-config.
# NB this creates an iso image that will be used by the NoCloud cloud-init datasource.
# see journalctl -u cloud-init
# see /run/cloud-init/*.log
# see https://cloudinit.readthedocs.io/en/latest/topics/examples.html#disk-setup
# see https://cloudinit.readthedocs.io/en/latest/topics/datasources/nocloud.html#datasource-nocloud
# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.9/docs/resources/cloudinit_disk
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/docs/resources/cloudinit_disk.md
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/internal/provider/cloudinit_disk_resource.go#L291-L341
resource "libvirt_cloudinit_disk" "debian" {
  name = "${var.prefix}-debian-cloudinit.iso"
  # NB in debian trixie (13) setting dhcp6 to false does not actually disable ipv6,
  #    it just prevents cloud-init from adding the iface eth0 inet6 dhcp line to the
  #    /etc/network/interfaces.d/50-cloud-init file. that inet6 ifupdown method no
  #    longer works in debian trixie (13) because it expects to find the dhclient
  #    binary which no longer exists by default (the isc-dhcp-client package is
  #    deprecated, and is no longer installed by default; it was replaced by the
  #    dhcpcd-base package, which provides the dhcpcd binary).
  #    see https://packages.debian.org/trixie/isc-dhcp-client
  #    see https://packages.debian.org/trixie/dhcpcd-base
  #    see https://packages.debian.org/trixie/ifupdown
  network_config = <<-EOF
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      dhcp6: false
  EOF
  meta_data      = <<-EOF
  EOF
  user_data      = <<-EOF
  #cloud-config
  manage_etc_hosts: true
  users:
    - name: vagrant
      lock_passwd: false
      ssh_authorized_keys:
        - ${jsonencode(trimspace(file("~/.ssh/id_rsa.pub")))}
  chpasswd:
    expire: false
    users:
      - name: vagrant
        password: '$6$rounds=4096$NQ.EmIrGxn$rTvGsI3WIsix9TjWaDfKrt9tm3aa7SX7pzB.PSjbwtLbsplk1HsVzIrZbXwQNce6wmeJXhCq9YFJHDx9bXFHH.'
  EOF
}

# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.9/docs/resources/volume
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/docs/resources/volume.md
resource "libvirt_volume" "debian_cloudinit" {
  pool = "default"
  name = "${var.prefix}-debian-cloudinit.iso"
  create = {
    content = {
      url = libvirt_cloudinit_disk.debian.path
    }
  }
}

# this uses the vagrant debian image imported from https://github.com/rgl/debian-vagrant.
# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.9/docs/resources/volume
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/docs/resources/volume.md
resource "libvirt_volume" "debian_root" {
  pool     = "default"
  name     = "${var.prefix}-debian-root.img"
  capacity = 16 * 1024 * 1024 * 1024 # GiB. the root FS is automatically resized by cloud-init growpart (see https://cloudinit.readthedocs.io/en/latest/topics/examples.html#grow-partitions).
  target = {
    format = {
      type = "qcow2"
    }
  }
  backing_store = {
    format = {
      type = "qcow2"
    }
    path = "/var/lib/libvirt/images/${var.debian_volume_name}"
  }
}

# see https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.9/docs/resources/domain
# see https://github.com/dmacvicar/terraform-provider-libvirt/blob/v0.9.9/docs/resources/domain.md
resource "libvirt_domain" "debian" {
  name        = "${var.prefix}-debian"
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
        <libosinfo:os id="${local.debian_os_id}"/>
      </libosinfo:libosinfo>
      EOF
  }
  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    firmware     = "efi"
  }
  cpu = {
    mode = "host-passthrough"
  }
  devices = {
    graphics = [
      {
        spice = {
          auto_port = true
          listeners = [
            {
              address = {}
            }
          ]
        }
      }
    ]
    videos = [
      {
        model = {
          type    = "qxl"
          primary = "yes"
          vram    = 65536
          ram     = 65536
          vga_mem = 16384
          heads   = 1
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
      {
        source = {
          spice_vmc = true
        }
        target = {
          virt_io = {
            name = "com.redhat.spice.0"
          }
        }
      }
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
            pool   = libvirt_volume.debian_root.pool
            volume = libvirt_volume.debian_root.name
          }
        }
        target = {
          bus = "scsi"
          dev = "sda"
        }
        wwn = format("000000000000aa%02x", 2)
      },
      {
        device = "cdrom"
        source = {
          volume = {
            pool   = libvirt_volume.debian_cloudinit.pool
            volume = libvirt_volume.debian_cloudinit.name
          }
        }
        target = {
          bus = "scsi"
          dev = "hdd"
        }
        serial = "cloudinit"
      },
    ]
    interfaces = [
      {
        type = "network"
        model = {
          type = "virtio"
        }
        source = {
          network = {
            network = libvirt_network.chr_ether2.name
          }
        }
      }
    ]
  }
}
