{
  description = "Homelab NixOS LXC Infrastructure";
  nixConfig = {
    extra-substituters = [
      "https://noctalia.cachix.org"
      "https://cache.nixos.org"
      "https://tranquil.cachix.org"
    ];
    extra-trusted-public-keys = [
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "tranquil.cachix.org-1:PoO+mGL6a6LcJiPakMDHN4E218/ei/7v2sxeDtNkSRg="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-sure = {
      type = "github";
      owner = "pjrm";
      repo = "nixpkgs";
      rev = "c7f1c6b2aedf787659fe5eba497e03f79c50e3cd";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
    };
    nixpkgs-freecad.url = "github:NixOS/nixpkgs/nixos-26.05";
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
      url = "github:noctalia-dev/noctalia/legacy-v4";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    niri.url = "github:epireyn/niri-flake";
    niri.inputs.nixpkgs.follows = "nixpkgs";

    nixarr.url = "github:nix-media-server/nixarr";
    # nixarr.inputs.nixpkgs.follows = "nixpkgs";

    # Tranquil PDS (atproto Personal Data Server).
    # Pinned to a release tag: this is your identity server, track releases
    # rather than main. Bump the tag + `nix flake update tranquil` to upgrade.
    # No `inputs.nixpkgs.follows` on purpose: keeping upstream's nixpkgs pin
    # means the store paths match tranquil.cachix.org, so the Rust build is
    # substituted instead of compiled locally.
    tranquil.url = "git+https://tangled.org/tranquil.farm/tranquil-pds?ref=refs/tags/v0.7.1";
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      inherit (nixpkgs) lib;
      pkgs = nixpkgs.legacyPackages.${system};

      inventory = import ./inventory { inherit lib; };

      # deploy-rs from nixpkgs' cache instead of building it from the input
      deployPkgs = import nixpkgs {
        inherit system;
        overlays = [
          inputs.deploy-rs.overlays.default
          (final: prev: {
            deploy-rs = {
              inherit (pkgs) deploy-rs;
              lib = prev.deploy-rs.lib;
            };
          })
        ];
      };
      deployLib = deployPkgs.deploy-rs.lib;

      lxc = import ./flake/lxc.nix {
        inherit
          self
          inputs
          system
          inventory
          deployLib
          ;
      };
      hosts = import ./flake/hosts.nix { inherit inputs inventory pkgs; };
    in
    {
      nixosModules.ssh-client = import ./modules/profiles/ssh-client.nix;

      nixosConfigurations = hosts.nixosConfigurations // lxc.nixosConfigurations;
      inherit (hosts) homeConfigurations;

      deploy.nodes = lxc.deployNodes;
      checks = builtins.mapAttrs (_: deployLib': deployLib'.deployChecks self.deploy) inputs.deploy-rs.lib;

      packages.${system} = {
        pve-zfs-backup = import ./pkgs/pve-zfs-backup.nix {
          inherit pkgs;
          sopsFile = ./secrets/pve2.enc.yaml;
        };
        sd-image-pi3 = self.nixosConfigurations.pi3-sendspin.config.system.build.sdImage;
      };
      packages.aarch64-linux.sd-image-pi3 =
        self.nixosConfigurations.pi3-sendspin.config.system.build.sdImage;

      apps.${system} = {
        pve-zfs-backup-install = {
          type = "app";
          program = "${self.packages.${system}.pve-zfs-backup}/bin/pve-zfs-backup-install";
        };
        default = self.apps.${system}.pve-zfs-backup-install;
      };

      formatter.${system} = pkgs.nixfmt;

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          sops
          age
          ssh-to-age
          nixos-rebuild
          pkgs.deploy-rs
        ];
      };
    };
}
