{
  description = "Homelab nix configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
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
      disko,
      headplane,
      old-nixpkgs,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = import nixpkgs { inherit system; };

      # Helper for standard service containers
      # This looks for logic in ./services/<name>/default.nix
      mkService = name: folder: extraModules: lib.nixosSystem {
        inherit system;
        specialArgs = { inherit self inputs; };
        modules = [
          ./services/${folder}/default.nix
          sops-nix.nixosModules.sops
          {
            boot.isContainer = true;
            networking.useDHCP = false;
            system.stateVersion = "25.11";
          }
        ] ++ extraModules;
      };

    in
    {
      # Custom Packages
      packages.${system}.default = pkgs.mkShellNoCC {
        packages = with pkgs; [
          nixos-generators
          nixos-install
          nixos-rebuild
          nixos-option
          nixos-install-tools
          mutagen
          sops
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
        # --- PHYSICAL HOSTS ---

        # Hypervisor (NAS)
        nixnas = lib.nixosSystem {
          inherit system;
          specialArgs = { inherit self inputs; };
          modules = [ ./hosts/nixnas/configuration.nix ];
        };

        # Desktop
        nixmaschine = lib.nixosSystem {
          inherit system;
          specialArgs = { inherit self inputs; };
          modules = [
            ./hosts/nixmaschine/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useUserPackages = true;
              home-manager.users.hajoha = import ./hosts/nixmaschine/home.nix;
              home-manager.extraSpecialArgs = { inherit inputs; };
            }
          ];
        };

        # --- SERVICE CONTAINERS (GENERATED) ---

        nixadguard      = mkService "nixadguard"      "adguardhome" [];
        nixpostgres     = mkService "nixpostgres"     "postgres" [];
        nixzitadel      = mkService "nixzitadel"      "zitadel" [];
        nixpaperless    = mkService "nixpaperless"    "paperless" [];
        nixhedgedoc     = mkService "nixhedgedoc"     "hedgedoc" [];
        nixlms          = mkService "nixlms"          "lms" [];
        nixinflux       = mkService "nixinflux"       "influxv2" [];
        nixgrafana      = mkService "nixgrafana"      "grafana" [];
        nixhomeassistant = mkService "nixhomeassistant" "home-assistant" [];
        nixwebserver    = mkService "nixwebserver"    "nginx" []; # Assuming webserver uses nginx logic
        nixnginx        = mkService "nixnginx"        "nginx" [];
#        nixcloud        = mkService "nixcloud"        "nextcloud" [];
#        nixnetbox       = mkService "nixnetbox"       "netbox" [];

        # Special Case: Headscale (Requires specific modules)
        nixheadscale = mkService "nixheadscale" "headscale" [
          headplane.nixosModules.headplane
          { nixpkgs.overlays = [ headplane.overlays.default ]; }
        ];

        # Special Case: Mininet (Requires old-nixpkgs)
        nixmininet = lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit self inputs;
            old-nixpkgs = old-nixpkgs.legacyPackages.${system};
          };
          modules = [ ./hosts/nixmininet/configuration.nix ];
        };
      };

      formatter.${system} = pkgs.nixfmt-tree;
    };
}