# Turns the plain data in ./nodes.nix into the `nodes` attrset that every
# service module receives via specialArgs. Each node keeps its original
# fields (ip, hostname, sub, port, …) and gains a generated `networking`.
{ lib }:
let
  inherit (lib) optionalAttrs recursiveUpdate foldl';

  baseDomain = "hackler.io";
  keycloakRealm = "main";

  # The "service" VLAN every LXC sits on.
  serviceNet = {
    interface = "service";
    prefixLength = 24;
    gateway = "10.60.1.1";
  };

  raw = import ./nodes.nix;

  # adguard resolves for everyone else
  defaultDns = [ raw.nix-adguard.ip ];

  mkNetworking =
    n:
    let
      dns = n.dns or defaultDns;
      tcp = n.tcp or [ ];
      udp = n.udp or [ ];
    in
    foldl' recursiveUpdate { } [
      {
        interfaces.${serviceNet.interface}.ipv4.addresses = [
          {
            address = n.ip;
            inherit (serviceNet) prefixLength;
          }
        ];
      }
      (optionalAttrs (n.gateway or true) {
        defaultGateway.address = serviceNet.gateway;
        defaultGateway.interface = serviceNet.interface;
      })
      (optionalAttrs (dns != null) { nameservers = dns; })
      (optionalAttrs (tcp != [ ]) { firewall.allowedTCPPorts = tcp; })
      (optionalAttrs (udp != [ ]) { firewall.allowedUDPPorts = udp; })
      (n.extraNetworking or { })
    ];

  mkNode =
    name: n:
    removeAttrs n [
      "tcp"
      "udp"
      "gateway"
      "dns"
      "extraNetworking"
    ]
    // {
      inherit name;
      networking = mkNetworking n;
      service = if n ? service then n.service else lib.removePrefix "nix-" name;
      deploy = n.deploy or { };
    };
in
{
  inherit baseDomain keycloakRealm;
  nodes = lib.mapAttrs mkNode raw;
}
