# Real machines (not inventory LXCs): workstation, VPS, Pi, and the
# standalone home-manager config for the work laptop.
{
  inputs,
  inventory,
  pkgs,
}:
let
  inherit (inputs) nixpkgs home-manager sops-nix;
  inherit (inputs) nixgl;
  inherit (inventory) baseDomain;
in
{
  nixosConfigurations = {
    pi3-sendspin = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs baseDomain; };
      modules = [
        ../hosts/pi3-sendspin/configuration.nix
        sops-nix.nixosModules.sops
      ];
    };

    nixmaschine = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs nixgl baseDomain; };
      modules = [
        ../hosts/nixmaschine/configuration.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.extraSpecialArgs = { inherit inputs nixgl baseDomain; };
          home-manager.users.hajoha.imports = [ ../hosts/nixmaschine/home.nix ];
        }
      ];
    };

    hetzner-vps-01 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ../hosts/hetzner-vps-01/configuration.nix
        inputs.disko.nixosModules.disko
        sops-nix.nixosModules.sops
      ];
    };
  };

  homeConfigurations.haa = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = { inherit inputs nixgl baseDomain; };
    modules = [
      ../hosts/nixarbeitsmaschine/home.nix
      {
        targets.genericLinux.enable = true;
        home.username = "haa";
        home.homeDirectory = "/home/haa";
      }
    ];
  };
}
