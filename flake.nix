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
    nvf = {
      url = "github:NotAShelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    headplane = {
      url = "github:tale/headplane";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      sops-nix,
      nvf,
      headplane,
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
        nixpostgres = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/nixpostgres/configuration.nix
            sops-nix.nixosModules.sops
          ];
        };
        nixzitadel = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/nixzitadel/configuration.nix
            sops-nix.nixosModules.sops
          ];
        };
        nixbuild = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/nixbuild/configuration.nix
          ];
        };
        nixheadscale = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/nixheadscale/configuration.nix
            sops-nix.nixosModules.sops
            headplane.nixosModules.headplane
            {
              # provides `pkgs.headplane`
              nixpkgs.overlays = [ headplane.overlays.default ];
            }
          ];
        };
        nixmininet = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/nixmininet/configuration.nix
          ];
        };
        nixhedgedoc = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/nixhedgedoc/configuration.nix
            sops-nix.nixosModules.sops
          ];
        };
      };

      formatter.${system} = pkgs.nixfmt-tree;
    };
}
