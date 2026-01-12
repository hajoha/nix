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
    old-nixpkgs = {
      type = "github";
      owner = "NixOS";
      repo = "nixpkgs";
      rev = "f294325aed382b66c7a188482101b0f336d1d7db";
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
      old-nixpkgs,
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
          mutagen
        ];
      };
      ryu = pkgs.callPackage ./pkgs/ryu/default.nix {
        inherit (pkgs.python3Packages)
          buildPythonPackage
          setuptools
          wheel
          lxml
          ncclient
          paramiko
          sqlalchemy
          ;
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
          specialArgs = {
            old-nixpkgs = old-nixpkgs.legacyPackages.${system};
          };
          modules = [
            ./hosts/nixmininet/configuration.nix
          ];
        };
        nixwebserver = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/nixwebserver/configuration.nix
            sops-nix.nixosModules.sops
          ];
        };
        nixpaperless = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/nixpaperless/configuration.nix
            sops-nix.nixosModules.sops
          ];
        };
        nixhedgedoc = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/nixhedgedoc/configuration.nix
            sops-nix.nixosModules.sops
          ];
        };
        nixlms = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/nixlms/configuration.nix
            sops-nix.nixosModules.sops
          ];
        };
        nixinflux = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/nixinflux/configuration.nix
            sops-nix.nixosModules.sops
          ];
        };
        nixgrafana = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/nixgrafana/configuration.nix
            sops-nix.nixosModules.sops
          ];
        };
      };

      formatter.${system} = pkgs.nixfmt-tree;
    };
}
