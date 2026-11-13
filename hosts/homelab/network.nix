# Host networking. The container VLAN interfaces (service, iot, ...) are
# created by modules/nixos/homelab-host.nix from params.vlans; this file only
# gives the host its own management address.
{
  lib,
  params,
  ...
}:
let
  m = params.management;
  # untagged on the trunk, or a dedicated VLAN interface "mgmt"
  iface = if m.vlan == null then params.trunk else "mgmt";
in
{
  # Stable NIC name, independent of PCI path / kernel naming.
  systemd.network.links."10-trunk" = {
    matchConfig.PermanentMACAddress = params.trunkMac;
    linkConfig.Name = params.trunk;
  };

  networking.useDHCP = false;

  networking.vlans = lib.mkIf (m.vlan != null) {
    mgmt = {
      id = m.vlan;
      interface = params.trunk;
    };
  };

  networking.interfaces.${iface}.ipv4.addresses = [
    {
      inherit (m) address prefixLength;
    }
  ];
  networking.defaultGateway = {
    address = m.gateway;
    interface = iface;
  };
  networking.nameservers = m.nameservers;

  networking.firewall.enable = true; # only ssh (services/ssh/root.nix)
}
