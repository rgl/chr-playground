#!/usr/bin/bash
set -euo pipefail

function usage {
  cat <<EOF
Usage:
  sudo $0 create <bridge-name> <slave-interface-name>
  sudo $0 delete <bridge-name> <slave-interface-name>

Example:
  sudo $0 create chr0 eth1
  sudo $0 delete chr0 eth1
EOF
  exit 1
}

function bridge_create {
  local bridge="$1"
  local slave="$2"

  ip link show "$slave" >/dev/null 2>&1 \
    || { echo "ERROR: The '$slave' interface does not exist." >&2; exit 1; }

  cat >"/etc/systemd/network/10-$bridge.netdev" <<EOF
[NetDev]
Name=$bridge
Kind=bridge
EOF

  cat >"/etc/systemd/network/10-$bridge.network" <<EOF
[Match]
Name=$bridge

[Network]
ConfigureWithoutCarrier=yes
EOF

  cat >"/etc/systemd/network/10-$slave.network" <<EOF
[Match]
Name=$slave

[Network]
Bridge=$bridge
EOF

  chmod 0644 \
    "/etc/systemd/network/10-$bridge.netdev" \
    "/etc/systemd/network/10-$bridge.network" \
    "/etc/systemd/network/10-$slave.network"

  systemctl restart systemd-networkd
}

function bridge_delete {
  local bridge="$1"
  local slave="$2"

  rm -f \
    "/etc/systemd/network/10-$bridge.netdev" \
    "/etc/systemd/network/10-$bridge.network" \
    "/etc/systemd/network/10-$slave.network"

  systemctl restart systemd-networkd

  ip link set "$slave" nomaster 2>/dev/null || true
  ip link del "$bridge" 2>/dev/null || true
}

[[ $EUID -eq 0 ]] || { echo "ERROR: This must be executed as root (sudo)." >&2; exit 1; }
[[ $# -ge 1 ]] || usage

ACTION="$1"
shift

case "$ACTION" in
  create)
    [[ $# -eq 2 ]] || usage
    bridge_create "$1" "$2"
    ;;
  delete)
    [[ $# -eq 2 ]] || usage
    bridge_delete "$1" "$2"
    ;;
  *)
    usage
    ;;
esac
