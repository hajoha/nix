# The homelab host (NixOS on bare metal, all services as containers) and its
# deploy-rs node.
#
#   deploy .#homelab                    deploy host + all containers
#   deploy .#homelab --dry-activate     dry run
#   nix build .#containers.nix-paperless  build a single container
{
  self,
  inputs,
  inventory,
  deployLib,
}:
let
  params = import ../hosts/homelab/params.nix;
in
{
  nixosConfiguration = inputs.nixpkgs.lib.nixosSystem {
    specialArgs = {
      inherit
        inputs
        self
        inventory
        params
        ;
    };
    modules = [
      ../hosts/homelab/configuration.nix
      ../modules/nixos/homelab.nix
      inventory.homelabConfig
      inputs.sops-nix.nixosModules.sops
    ];
  };

  deployNode = {
    hostname = params.management.address;
    magicRollback = true;
    autoRollback = true;
    # container restarts (keycloak, sure db:prepare) run inside activation
    activationTimeout = 900;
    confirmTimeout = 120;
    profiles.system = {
      user = "root";
      path = deployLib.activate.nixos self.nixosConfigurations.homelab;
    };
  };
}
