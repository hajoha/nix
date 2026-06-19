{
  description = "Homelab NixOS LXC Infrastructure";
  nixConfig = {
    extra-substituters = [
      "https://noctalia.cachix.org"
      "https://cache.nixos.org"
    ];
    extra-trusted-public-keys = [
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur.url = "github:nix-community/NUR";
    nixgl.url = "github:nix-community/nixGL";
    nvf = {
      url = "github:notashelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # headplane = {
    #   url = "github:tale/headplane";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    openwrt-imagebuilder.url = "github:astro/nix-openwrt-imagebuilder";
    old-nixpkgs = {
      type = "github";
      owner = "NixOS";
      repo = "nixpkgs";
      rev = "f294325aed382b66c7a188482101b0f336d1d7db";
    };
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    niri.url = "github:sodiboo/niri-flake";
    niri.inputs.nixpkgs.follows = "nixpkgs";
    nixarr.url = "github:nix-media-server/nixarr";
  };

  outputs =
    {
      self,
      nixpkgs,
      deploy-rs,
      home-manager,
      sops-nix,
      openwrt-imagebuilder,
      nixgl,
      noctalia,
      niri,
      nixarr,
      old-nixpkgs,

      ...
    }@inputs:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      network = import ./network.nix;
      pkgs = nixpkgs.legacyPackages.${system};
      nodes = network.nodes;
      baseDomain = network.baseDomain;
      keycloakRealm = "main";
      pve2Secret = ./secrets/pve2.enc.yaml;

      deployLib = deploy-rs.lib.${system};

      # ── SSH alias helpers ─────────────────────────────────────────────────
      # LXC nodes: "nix-nginx"      → "home-nix-nginx"   (from ~/.ssh/config)
      # Hetzner:   "hetzner-vps-01" → "hetzner-vps-01"   (from ~/.ssh/config)
      # deploy-rs passes hostname straight to SSH, so ProxyJump, IdentityFile,
      # Port etc. in your ssh config are all respected automatically.
      lxcAlias = name: "home-${name}";

      # ── mkLXC ─────────────────────────────────────────────────────────────
      mkLXC =
        name: servicePath: extraModules:
        lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit
              inputs
              nodes
              baseDomain
              keycloakRealm
              self
              ;
          };
          modules = [
            ./modules/profiles/lxc-base.nix
            ./services/alloy/default.nix
            servicePath
            sops-nix.nixosModules.sops
            {
              networking = nodes.${name}.networking;
              sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
              documentation.enable = false;
              documentation.nixos.enable = false;
            }
          ]
          ++ extraModules;
        };

      # ── mkNode ────────────────────────────────────────────────────────────
      # Used only for LXC containers and hetzner-vps-01.
      # `hostname` is the SSH alias/host from ~/.ssh/config.
      mkNode =
        hostname: nixosCfg: overrides:
        {
          inherit hostname;
          # sshUser = "root";
          magicRollback = true;
          autoRollback = true;
          activationTimeout = 300;
          confirmTimeout = 60;
          profiles.system = {
            user = "root";
            path = deployLib.activate.nixos nixosCfg;
          };

          nix.settings.trusted-public-keys = [
            "nix-build:xkoryMgWD1pUN66/xhSmrYNhkyHZtazu4DHGaRySCHM="
            "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          ];
          nix.settings.auto-optimise-store = true;
        }
        // overrides;

    in
    {

      nixosModules.ssh-client = import ./modules/profiles/ssh-client.nix;
      nixosConfigurations = {

        # ── Managed with nixos-rebuild (not deploy-rs) ─────────────────────
        # nixos-rebuild switch --flake .#<name> --build-host ... --target-host ...
        nixmaschine = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs nixgl baseDomain; }; # Added missing specialArgs your home config needs
          modules = [
            ./hosts/nixmaschine/configuration.nix
            inputs.home-manager.nixosModules.home-manager # 1. Import the Home Manager NixOS module
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs nixgl baseDomain; }; # Passes flake inputs to home.nix

              # 2. Point it directly to your home.nix file
              home-manager.users.hajoha = import ./hosts/nixmaschine/home.nix;
            }
          ];
        };
        hetzner-vps-01 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/hetzner-vps-01/configuration.nix
            inputs.disko.nixosModules.disko
            sops-nix.nixosModules.sops
          ];
        };

        # ── LXC service containers (deployed via deploy-rs) ────────────────

        nix-adguard = mkLXC "nix-adguard" ./services/adguardhome/default.nix [ ];
        nix-postgres = mkLXC "nix-postgres" ./services/postgres/default.nix [ ];
        nix-paperless = mkLXC "nix-paperless" ./services/paperless/default.nix [ ];
        nix-hedgedoc = mkLXC "nix-hedgedoc" ./services/hedgedoc/default.nix [ ];
        nix-immich = mkLXC "nix-immich" ./services/immich/default.nix [ ];
        nix-influx = mkLXC "nix-influx" ./services/influxv2/default.nix [ ];
        nix-grafana = mkLXC "nix-grafana" ./services/grafana/default.nix [ ];
        nix-keycloak = mkLXC "nix-keycloak" ./services/keycloak/default.nix [ ];
        nix-listmonk = mkLXC "nix-listmonk" ./services/listmonk/default.nix [ ];
        nix-loki = mkLXC "nix-loki" ./services/loki/default.nix [ ];
        nix-unifi-controller = mkLXC "nix-unifi-controller" ./services/unifi-controller/default.nix [ ];
        nix-arr = mkLXC "nix-arr" ./services/nixarr/default.nix [ nixarr.nixosModules.default ];
        nix-opencloud = mkLXC "nix-opencloud" ./services/opencloud/default.nix [ ];
        nix-homeassistant = mkLXC "nix-homeassistant" ./services/hass/default.nix [ ];
        nix-nginx = mkLXC "nix-nginx" ./services/nginx/default.nix [ ];
        nix-headscale = mkLXC "nix-headscale" ./services/headscale/default.nix [ ];
        nix-build = mkLXC "nix-build" ./services/build/default.nix [ ];
      };

      # ══════════════════════════════════════════════════════════════════════
      # deploy-rs — LXC containers + Hetzner VPS only
      #
      # deploy .#nix-nginx                   deploy single LXC
      # deploy .#hetzner-vps-01              deploy Hetzner VPS
      # deploy . --skip-checks               skip nix flake check
      # deploy .#nix-nginx --dry-activate    dry run
      # deploy .#nix-nginx -- --builders 'ssh://home-nix-build x86_64-linux'
      # ══════════════════════════════════════════════════════════════════════
      deploy.nodes = {

        # SSH alias "hetzner-vps-01" must exist in ~/.ssh/config
        # hetzner-vps-01 = mkNode "hetzner-vps-01" self.nixosConfigurations.hetzner-vps-01 {
        #   activationTimeout = 600;
        #   sshUser = "mng";
        # };

        # LXC nodes — SSH aliases are "home-nix-<name>" per ~/.ssh/config
        nix-adguard = mkNode (lxcAlias "nix-adguard") self.nixosConfigurations.nix-adguard { };
        nix-postgres = mkNode (lxcAlias "nix-postgres") self.nixosConfigurations.nix-postgres { };
        nix-paperless = mkNode (lxcAlias "nix-paperless") self.nixosConfigurations.nix-paperless { };
        nix-hedgedoc = mkNode (lxcAlias "nix-hedgedoc") self.nixosConfigurations.nix-hedgedoc { };
        nix-immich = mkNode (lxcAlias "nix-immich") self.nixosConfigurations.nix-immich { };
        nix-influx = mkNode (lxcAlias "nix-influx") self.nixosConfigurations.nix-influx { };
        nix-grafana = mkNode (lxcAlias "nix-grafana") self.nixosConfigurations.nix-grafana { };
        nix-keycloak = mkNode (lxcAlias "nix-keycloak") self.nixosConfigurations.nix-keycloak {
          activationTimeout = 600;
        };
        nix-listmonk = mkNode (lxcAlias "nix-listmonk") self.nixosConfigurations.nix-listmonk { };
        nix-loki = mkNode (lxcAlias "nix-loki") self.nixosConfigurations.nix-loki { };
        nix-unifi-controller =
          mkNode (lxcAlias "nix-unifi-controller") self.nixosConfigurations.nix-unifi-controller
            { };
        nix-arr = mkNode (lxcAlias "nix-arr") self.nixosConfigurations.nix-arr { };
        nix-opencloud = mkNode (lxcAlias "nix-opencloud") self.nixosConfigurations.nix-opencloud { };
        nix-homeassistant =
          mkNode (lxcAlias "nix-homeassistant") self.nixosConfigurations.nix-homeassistant
            { };
        nix-nginx = mkNode (lxcAlias "nix-nginx") self.nixosConfigurations.nix-nginx { };
        nix-headscale = mkNode (lxcAlias "nix-headscale") self.nixosConfigurations.nix-headscale { };
        nix-build = mkNode (lxcAlias "nix-build") self.nixosConfigurations.nix-build { };
      };

      checks = builtins.mapAttrs (_system: lib': lib'.deployChecks self.deploy) deploy-rs.lib;

      # ── rest of outputs unchanged ──────────────────────────────────────────

      packages.${system} = {
        pve-zfs-backup = import ./pkgs/pve-zfs-backup.nix {
          inherit pkgs;
          sopsFile = pve2Secret;
        };
      };

      apps.${system} = {
        pve-zfs-backup-install = {
          type = "app";
          program = "${self.packages.${system}.pve-zfs-backup}/bin/pve-zfs-backup-install";
        };
        default = self.apps.${system}.pve-zfs-backup-install;
      };

      homeConfigurations = {
        "haa" = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = { inherit inputs nixgl baseDomain; };
          modules = [
            ./hosts/nixarbeitsmaschine/home.nix
            {
              targets.genericLinux.enable = true;
              home.username = "haa";
              home.homeDirectory = "/home/haa";
            }
          ];
        };

      };

      formatter.${system} = pkgs.nixfmt;

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          sops
          age
          ssh-to-age
          nixos-rebuild
          deploy-rs.packages.${system}.deploy-rs
        ];
      };
    };
}
