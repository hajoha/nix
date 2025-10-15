{
  description = "Homelab nix configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur.url = "github:nix-community/nur";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      sops-nix,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
      };
    in
    {
      packages.${system}.default = pkgs.mkShellNoCC {
        packages = with pkgs; [
          nixos-generators
          nixos-install
          nixos-rebuild
          nixos-option
        ];
      };
      nixosConfigurations = {
        nixmaschine = nixpkgs.lib.nixosSystem {
          inherit system;
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
            sops-nix.nixosModules.sops
          ];
        };
        nixnginx = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/nixnginx/configuration.nix
            sops-nix.nixosModules.sops
          ];
        };
      };

      formatter.${system} = pkgs.nixfmt-tree;
    };
}
