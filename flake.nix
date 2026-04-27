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
    nur = {
      url = "github:nix-community/NUR";
    };
    nixgl.url = "github:nix-community/nixGL";

    # Also add nvf if you haven't, since your home.nix uses it
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
    headplane = {
      url = "github:tale/headplane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs = {
        nixpkgs = {
          follows = "nixpkgs";
        };
      };
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
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      sops-nix,
      headplane,
      openwrt-imagebuilder,
      # otbr-pr,
      nixgl,
      noctalia,
      niri,
      old-nixpkgs,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;

      # 1. Import the central network map
      network = import ./network.nix;
      pkgs = nixpkgs.legacyPackages.${system};

      # 2. Extract variables for local scope to fix "undefined variable" errors
      nodes = network.nodes;
      baseDomain = network.baseDomain;
      keycloakRealm = "main";
      pve2Secret = ./secrets/pve2.enc.yaml;

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
              keycloakRealm
              self
              ;
          };
          modules = [
            # Base profile for Proxmox LXC plumbing
            ./modules/profiles/lxc-base.nix
            ./services/alloy/default.nix
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
      packages.${system} = {
        pve-zfs-backup = import ./pkgs/pve-zfs-backup.nix {
          inherit pkgs;
          sopsFile = pve2Secret;
        };
        fritz7530-image =
          let
            # 1. Define 'profiles' here so 'config' can see it
            profiles = openwrt-imagebuilder.lib.profiles { inherit pkgs; };

            # 3. Define the config using the profiles we just initialized
            config = profiles.identifyProfile "avm_fritzbox-7530" // {
              release = "25.12.2";
              packages = [
                "apk-mbedtls"
                "ath10k-board-qca4019"
                "ath10k-firmware-qca4019-ct"
                "base-files"
                "ca-bundle"
                "dnsmasq"
                "dropbear"
                "firewall4"
                "fstools"
                "ddns-scripts"
                "kmod-ath10k-ct"
                "kmod-gpio-button-hotplug"
                "kmod-leds-gpio"
                "kmod-nft-offload"
                "kmod-usb-dwc3"
                "kmod-usb-dwc3-qcom"
                "kmod-usb3"
                "libc"
                "libgcc"
                "libustream-mbedtls"
                "logd"
                "mtd"
                "netifd"
                "nftables"
                "odhcp6c"
                "odhcpd-ipv6only"
                "ppp"
                "ppp-mod-pppoe"
                "procd-ujail"
                "uboot-envtools"
                "uci"
                "uclient-fetch"
                "tcpdump"
                "urandom-seed"
                "urngd"
                "wpad-basic-mbedtls"
                "fritz-caldata"
                "fritz-tffs-nand"
                "ltq-vdsl-vr11-app"
                "luci"
                "luci-app-attendedsysupgrade"
                "tailscale"
                "kmod-wireguard"
                "wireguard-tools"
                "luci-proto-wireguard"
                "iperf3"
                "curl"
                "luci-app-ddns"
              ];
              extraImageNames = [ "initramfs-fit-uImage.itb" ];
              # 4. Inject secrets via uci-defaults
              files = pkgs.runCommand "image-files" { } ''
                mkdir -p $out/etc/uci-defaults
                cat > $out/etc/uci-defaults/99-custom <<EOF
                uci -q batch << EOI
                set system.@system[0].hostname='testap'
                commit
                EOI
                EOF
              '';
            };
          in
          # 5. Call the builder with our defined config
          openwrt-imagebuilder.lib.build config;

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
          extraSpecialArgs = {
            inherit inputs;
            inherit nixgl;
            inherit baseDomain;
          };
          modules = [
            # Point this to your home.nix file
            ./hosts/nixarbeitsmaschine/home.nix

            {
              # Required for Ubuntu/Non-NixOS
              targets.genericLinux.enable = true;
              home.username = "haa";
              home.homeDirectory = "/home/haa";

            }
          ];
        };
      };
      nixosConfigurations = {
        # --- PHYSICAL HOSTS ---

        hetzner-vps-01 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            ./hosts/hetzner-vps-01/configuration.nix
            inputs.disko.nixosModules.disko
            sops-nix.nixosModules.sops
          ];
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
        nix-paperless = mkLXC "nix-paperless" ./services/paperless/default.nix [ ];
        nix-hedgedoc = mkLXC "nix-hedgedoc" ./services/hedgedoc/default.nix [ ];
        nix-immich = mkLXC "nix-immich" ./services/immich/default.nix [ ];
        nix-influx = mkLXC "nix-influx" ./services/influxv2/default.nix [ ];
        nix-grafana = mkLXC "nix-grafana" ./services/grafana/default.nix [ ];
        nix-keycloak = mkLXC "nix-keycloak" ./services/keycloak/default.nix [ ];
        nix-listmonk = mkLXC "nix-listmonk" ./services/listmonk/default.nix [ ];
        nix-loki = mkLXC "nix-loki" ./services/loki/default.nix [ ];

        nix-unifi-controller = mkLXC "nix-unifi-controller" ./services/unifi-controller/default.nix [ ];

        nix-opencloud = mkLXC "nix-opencloud" ./services/opencloud/default.nix [ ];
        nix-homeassistant = mkLXC "nix-homeassistant" ./services/hass/default.nix [ ];
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
          ssh-to-age
          nixos-rebuild
        ];
      };
    };

}
