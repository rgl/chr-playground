# About

[![Lint](https://github.com/rgl/chr-playground/actions/workflows/lint.yml/badge.svg)](https://github.com/rgl/chr-playground/actions/workflows/lint.yml)

My [MikroTik Cloud Hosted Router (CHR) (aka RouterOS)](https://manual.mikrotik.com/docs/introduction) playground.

This uses the [terraform-routeros provider](https://github.com/terraform-routeros/terraform-provider-routeros) to configure the router.

Be aware that the terraform-routeros provider does not handle all the CHR API entities properties (especially when you use the latest CHR versions) and will show warnings alike:

```
╷
│ Warning: Field 'actual_path_cost' not found in the schema
│
│   with routeros_interface_bridge_port.lan_ether2,
│   on main.tf line 51, in resource "routeros_interface_bridge_port" "lan_ether2":
│   51: resource "routeros_interface_bridge_port" "lan_ether2" {
│
│ [MikrotikResourceDataToTerraform] The field was lost during the Schema development: ▷ 'actual_path_cost': '20000' ◁
╵
```

## Usage

Install Ubuntu, QEMU, libvirt, and Terraform.

Create and install the [base Debian 13 UEFI vagrant box](https://github.com/rgl/debian-vagrant).

Create `chr-{version}.qcow2` libvirt volume:

```bash
pushd infra
./create-chr-volume.sh
popd
```

Create the infrastructure:

```bash
pushd infra
terraform init
terraform apply
popd
```

Configure CHR:

```bash
pushd config
terraform init
terraform apply
popd
```

Show information about the `chr` guest:

```bash
virsh dumpxml chr-playground-chr
virsh qemu-agent-command chr-playground-chr '{"execute":"guest-info"}' --pretty
virsh qemu-agent-command chr-playground-chr '{"execute":"guest-get-osinfo"}' --pretty
virsh qemu-agent-command chr-playground-chr '{"execute":"guest-network-get-interfaces"}' --pretty
./qemu-agent-chr-guest-exec chr-playground-chr /system/resource/print
```

Access the [CHR WebFig management interface](https://manual.mikrotik.com/docs/management-tools/webfig):

```bash
pushd config
xdg-open "$(terraform output -raw chr_url)"
popd
```

Play with the [REST API](https://manual.mikrotik.com/docs/developer-guides/rest-api):

```bash
pushd config
curl -su admin: "http://$(terraform output -raw chr_ip)/rest/system/resource" | jq
curl -su admin: "http://$(terraform output -raw chr_ip)/rest/ip/service" \
  | jq -r '["Name","Protocol","Port","Disabled"], (.[] | [.name,.proto,.port,.disabled]) | @tsv' \
  | column -t -s $'\t'
curl -su admin: "http://$(terraform output -raw chr_ip)/rest/interface?type=ether" \
  | jq -r '["Name","MAC Address"], (.[] | [.name,."mac-address"]) | @tsv' \
  | column -t -s $'\t'
curl -su admin: "http://$(terraform output -raw chr_ip)/rest/ip/arp" | jq
curl -su admin: "http://$(terraform output -raw chr_ip)/rest/ip/neighbor" | jq
curl -su admin: "http://$(terraform output -raw chr_ip)/rest/ip/dhcp-server/lease" \
  | jq -r '["Server","Status","MAC-Address","Address","Host-Name"], (.[] | [.server,.status,."mac-address",.address,."host-name"]) | @tsv' \
  | column -t -s $'\t'
popd
```

Play with the [CLI](https://manual.mikrotik.com/docs/cli-reference/):

```bash
pushd config
ssh "admin@$(terraform output -raw chr_ip)" /ip dhcp-server lease print
ssh "admin@$(terraform output -raw chr_ip)" /ip dns print
ssh "admin@$(terraform output -raw chr_ip)" /ip dns cache all print
popd
```

Show the configuration:

```bash
pushd config
ssh "admin@$(terraform output -raw chr_ip)" /export
ssh "admin@$(terraform output -raw chr_ip)" /export verbose #show-sensitive
popd
```

Using the `chr` router host as the ssh jump host, access the `debian` host:

```bash
pushd config
ssh -J "admin@$(terraform output -raw chr_ip)" "vagrant@$(terraform output -raw debian_fqdn)"
echo $SSH_CONNECTION
cat /etc/os-release
exit
popd
```

Destroy everything:

```bash
pushd config
terraform destroy
popd
pushd infra
terraform destroy
popd
```
