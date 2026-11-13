# Turns the plain data in ./nodes.nix into `nodes` (one per container on the
# homelab host). Each node keeps its original fields (ip, hostname, sub,
# port, …) and gains a generated `networking`.
{ lib }:
let
  inherit (lib) optionalAttrs recursiveUpdate foldl';

  baseDomain = "hackler.io";
  keycloakRealm = "main";

  # The "service" VLAN every container sits on.
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
      "db"
      "tcp"
      "udp"
      "gateway"
      "dns"
      "extraNetworking"
      "autoStart"
    ]
    // {
      inherit name;
      networking = mkNetworking n;
      service = if n ? service then n.service else lib.removePrefix "nix-" name;
      autoStart = n.autoStart or true;
    };
  nodes = lib.mapAttrs mkNode raw;

  # Service names that get a database on nix-postgres (see `db` in nodes.nix).
  databases = lib.mapAttrsToList (name: _: nodes.${name}.service) (
    lib.filterAttrs (_: n: n.db or false) raw
  );
in
{
  inherit
    baseDomain
    keycloakRealm
    nodes
    databases
    ;

  # Module that fills the typed `homelab.*` options (modules/nixos/homelab.nix)
  # in every container.
  homelabConfig.homelab = {
    domain = baseDomain;
    sso.realm = keycloakRealm;
    inherit databases;
    nodes = lib.mapAttrs (
      _: n:
      {
        inherit (n) ip port hostname;
      }
      // lib.optionalAttrs (n ? sub) { inherit (n) sub; }
    ) nodes;
  };
}
