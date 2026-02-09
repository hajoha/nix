{
  description = "Homelab NixOS LXC Infrastructure";

  inputs = {
    otbr-pr = {
      url = "github:mrene/nixpkgs/openthread-border-router";
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
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
      headplane,
      otbr-pr,
      old-nixpkgs,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;

      # 1. Import the central network map
      network = import ./network.nix;

      # 2. Extract variables for local scope to fix "undefined variable" errors
      nodes = network.nodes;
      baseDomain = network.baseDomain;

      # 3. Unified LXC Generator
      # name: The key from network.nix (e.g., "nix-nginx")
      # servicePath: Path to the default.nix of the service
      # extraModules: List of additional modules (overlays, headplane, etc.)
      mkLXC =
        name: servicePath: extraModules:
        lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit
              inputs
              nodes
              baseDomain
              self
              ;
          };
          modules = [
            # Base profile for Proxmox LXC plumbing
            ./modules/profiles/lxc-base.nix

            # The service logic
            servicePath

            # Global secrets management
            sops-nix.nixosModules.sops

            {
              # Apply networking from network.nix automatically
              networking = nodes.${name}.networking;

              # Ensure SOPS can use the host's SSH key for decryption inside LXC
              sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

              # Disable documentation to keep container size small
              documentation.enable = false;
              documentation.nixos.enable = false;

            }
          ]
          ++ extraModules;
        };

    in
    {
      nixosConfigurations = {
        # --- PHYSICAL HOSTS ---
        nixnas = lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit
              self
              inputs
              nodes
              baseDomain
              ;
          };
          modules = [ ./hosts/nixnas/configuration.nix ];
        };

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

        # --- LXC SERVICE CONTAINERS ---
        # Syntax: name = mkLXC "network-key" ./service-path [extra-modules];

        nix-adguard = mkLXC "nix-adguard" ./services/adguardhome/default.nix [ ];
        nix-postgres = mkLXC "nix-postgres" ./services/postgres/default.nix [ ];
        nix-zitadel = mkLXC "nix-zitadel" ./services/zitadel/default.nix [ ];
        nix-paperless = mkLXC "nix-paperless" ./services/paperless/default.nix [ ];
        nix-hedgedoc = mkLXC "nix-hedgedoc" ./services/hedgedoc/default.nix [ ];
        nix-influx = mkLXC "nix-influx" ./services/influxv2/default.nix [ ];
        nix-grafana = mkLXC "nix-grafana" ./services/grafana/default.nix [ ];
        nix-unifi-controller = mkLXC "nix-unifi-controller" ./services/unifi-controller/default.nix [ ];
        nix-homeassistant = mkLXC "nix-homeassistant" ./services/homeassistant/default.nix [
          # This pulls the actual .nix file from the PR branch
          "${inputs.otbr-pr}/nixos/modules/services/home-automation/openthread-border-router.nix"
          {
            nixpkgs.overlays = [
              (final: prev: {
                # This maps the package from the PR branch into the current pkgs
                openthread-border-router = inputs.otbr-pr.legacyPackages.${system}.openthread-border-router;
              })
            ];
          }
        ];
        nix-nginx = mkLXC "nix-nginx" ./services/nginx/default.nix [ ];
        nix-netbox = mkLXC "nix-netbox" ./services/netbox/default.nix [ ];

        # Headscale with Headplane UI & Overlays
        nix-headscale = mkLXC "nix-headscale" ./services/headscale/default.nix [
          headplane.nixosModules.headplane
          { nixpkgs.overlays = [ headplane.overlays.default ]; }
        ];

        # Specialized VM (Non-LXC)
        nixmininet = lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit self inputs;
            old-nixpkgs = old-nixpkgs.legacyPackages.${system};
          };
          modules = [ ./hosts/nixmininet/configuration.nix ];
        };
      };

      # Formatting tool
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-rfc-style;

      # Development Shell
      devShells.${system}.default = nixpkgs.legacyPackages.${system}.mkShell {
        packages = with nixpkgs.legacyPackages.${system}; [
          sops
          age
          nixos-rebuild
        ];
      };
    };
}
