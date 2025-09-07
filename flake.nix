{
  description = "A simple NixOS flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur.url = "github:nix-community/nur";
    nvf = {
      url = "github:NotAShelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };



  outputs = { self, nixpkgs, home-manager, nvf, ... }@inputs:
    {
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixpkgs-fmt;
      nixosConfigurations = {
        nixmaschine = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            #./modules/home-manager/open-webui/open-webui.nix
            ./hosts/nixmaschine/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useUserPackages = true;
              home-manager.users.hajoha = import ./hosts/nixmaschine/home.nix;
              home-manager.extraSpecialArgs = { inherit inputs; };
            }

          ];

        };
        nixcloud = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/nixcloud/configuration.nix
          ];
        };
        nixadguard = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/nixadguard/configuration.nix
          ];
        };
        nixnginx = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/nixnginx/configuration.nix
          ];
        };
      };
    };
}
