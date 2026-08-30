#!/usr/bin/bash
set -euo pipefail
set -x

# download the chr image and upload it to a libvirt volume.
# see https://mikrotik.com/download/chr
CHR_VERSION='7.21.5'
CHR_URL="https://download.mikrotik.com/routeros/$CHR_VERSION/chr-$CHR_VERSION.img.zip"
rm -rf "tmp/chr-$CHR_VERSION-box"
install -d "tmp/chr-$CHR_VERSION-box"
pushd "tmp/chr-$CHR_VERSION-box"
wget -qO "chr-$CHR_VERSION.img.zip" "$CHR_URL"
unzip "chr-$CHR_VERSION.img.zip"
fdisk -l "chr-$CHR_VERSION.img"
qemu-img convert -f raw -O qcow2 "chr-$CHR_VERSION.img" "chr-$CHR_VERSION.qcow2"
qemu-img info "chr-$CHR_VERSION.qcow2"
chr_volume_name="chr-$CHR_VERSION.qcow2"
if [ -n "$(virsh vol-list default | grep --fixed-strings "$chr_volume_name")" ]; then
  virsh vol-delete --pool default "$chr_volume_name"
fi
virsh vol-create-as default "$chr_volume_name" 10M
virsh vol-upload --pool default "$chr_volume_name" "$chr_volume_name"
popd
cat >terraform.tfvars <<EOF
chr_version     = "$CHR_VERSION"
chr_volume_name = "$chr_volume_name"
EOF
