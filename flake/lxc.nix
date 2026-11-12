# Builds one nixosConfiguration and (optionally) one deploy-rs node for every
# entry in ./inventory/nodes.nix that has a `service`.
#
#   deploy .#nix-nginx                   deploy single LXC
#   deploy .                             deploy every node with deploy != false
#   deploy . --skip-checks               skip nix flake check
#   deploy .#nix-nginx --dry-activate    dry run
#   deploy .#nix-nginx -- --builders 'ssh://home-nix-build x86_64-linux'
{
  self,
  inputs,
  system,
  inventory,
  deployLib,
}:
let
  inherit (inputs) nixpkgs sops-nix;
  inherit (nixpkgs) lib;
  inherit (inventory) nodes baseDomain keycloakRealm;

  # Flake modules a service needs on top of the shared base.
  extraModules = {
    nix-arr = [ inputs.nixarr.nixosModules.default ];
    nix-tranquil = [ inputs.tranquil.nixosModules.default ];
  };

  # Typed inventory for the homelab module (modules/nixos/homelab.nix).
  homelabConfig.homelab = {
    domain = baseDomain;
    sso.realm = keycloakRealm;
    inherit (inventory) databases;
    nodes = lib.mapAttrs (
      _: n:
      {
        inherit (n) ip port hostname;
      }
      // lib.optionalAttrs (n ? sub) { inherit (n) sub; }
    ) nodes;
  };

  lxcNodes = lib.filterAttrs (_: n: n.service != null) nodes;

  mkLXC =
    name: node:
    lib.nixosSystem {
      specialArgs = { inherit inputs self; };
      modules = [
        ../modules/nixos/homelab.nix
        homelabConfig
        ../modules/profiles/lxc-base.nix
        ../services/alloy/default.nix
        { nixpkgs.hostPlatform = system; }
        ../services/${node.service}/default.nix
        sops-nix.nixosModules.sops
        {
          networking = node.networking;
          sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
          documentation.enable = false;
          documentation.nixos.enable = false;
        }
      ]
      ++ (extraModules.${name} or [ ]);
    };

  # SSH alias is "home-<name>" (from ~/.ssh/config); deploy-rs passes it
  # straight to ssh, so ProxyJump, IdentityFile, Port etc. are respected.
  mkDeployNode =
    name: node:
    {
      hostname = "home-${name}";
      magicRollback = true;
      autoRollback = true;
      activationTimeout = 300;
      confirmTimeout = 60;
      profiles.system = {
        user = "root";
        path = deployLib.activate.nixos self.nixosConfigurations.${name};
      };
    }
    // node.deploy;
in
{
  nixosConfigurations = lib.mapAttrs mkLXC lxcNodes;
  deployNodes = lib.mapAttrs mkDeployNode (lib.filterAttrs (_: n: n.deploy != false) lxcNodes);
}
