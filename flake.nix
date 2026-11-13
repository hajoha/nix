{
  description = "Homelab: NixOS host with service containers, plus workstations";
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

      homelab = import ./flake/homelab.nix {
        inherit
          self
          inputs
          inventory
          deployLib
          ;
      };
      hosts = import ./flake/hosts.nix { inherit inputs inventory pkgs; };

      # .sops.yaml is generated from the inventory (see inventory/sops.nix).
      sopsYaml = pkgs.writeText "sops.yaml" (import ./inventory/sops.nix { inherit lib; });
    in
    {
      nixosModules.ssh-client = import ./modules/nixos/ssh-client.nix;

      nixosConfigurations = hosts.nixosConfigurations // {
        homelab = homelab.nixosConfiguration;
      };
      inherit (hosts) homeConfigurations;

      deploy.nodes.homelab = homelab.deployNode;

      # One container's system, e.g. `nix build .#containers.nix-paperless`
      legacyPackages.${system}.containers = lib.mapAttrs (
        _: c: c.config.system.build.toplevel
      ) self.nixosConfigurations.homelab.config.containers;
      checks =
        lib.recursiveUpdate
          (builtins.mapAttrs (_: deployLib': deployLib'.deployChecks self.deploy) inputs.deploy-rs.lib)
          {
            ${system}.sops-config = pkgs.runCommand "sops-config-up-to-date" { } ''
              if ! diff -u ${./.sops.yaml} ${sopsYaml}; then
                echo ".sops.yaml is out of date, run: nix run .#sops-config" >&2
                exit 1
              fi
              touch $out
            '';
          };

      packages.${system} = {
        sd-image-pi3 = self.nixosConfigurations.pi3-sendspin.config.system.build.sdImage;
      };
      packages.aarch64-linux.sd-image-pi3 =
        self.nixosConfigurations.pi3-sendspin.config.system.build.sdImage;

      apps.${system} = {
        # Regenerate .sops.yaml from the inventory (run from the repo root).
        sops-config = {
          type = "app";
          program = "${pkgs.writeShellScript "sops-config" ''
            cp --no-preserve=mode ${sopsYaml} .sops.yaml
            echo "wrote .sops.yaml; re-encrypt changed files with: sops updatekeys <file>"
          ''}";
        };

        # Ssh host key (= sops identity) for a new homelab container, made
        # here instead of on the host: writes `age` into inventory/nodes.nix
        # and the private key into hosts/homelab/container-keys.enc.json.
        #   nix run .#new-node-key nix-foo
        new-node-key = {
          type = "app";
          program = lib.getExe (
            pkgs.writeShellApplication {
              name = "new-node-key";
              runtimeInputs = with pkgs; [
                sops
                openssh
                ssh-to-age
                jq
                gawk
                coreutils
                git
              ];
              text = ''
                node=''${1:?usage: nix run .#new-node-key <node>}
                file=hosts/homelab/container-keys.enc.json
                nodes=inventory/nodes.nix
                [ -f "$nodes" ] || { echo "run this from the repo root" >&2; exit 1; }
                grep -qx "  $node = {" "$nodes" ||
                  { echo "no node '$node' in $nodes, add it first" >&2; exit 1; }
                if [ -f "$file" ] && jq -e --arg n "$node" 'has($n)' "$file" >/dev/null; then
                  echo "$node already has a key in $file" >&2; exit 1
                fi

                # creation rules must be current before encrypting
                nix run .#sops-config >/dev/null

                tmp=$(mktemp -d -p "''${XDG_RUNTIME_DIR:-/tmp}")
                trap 'rm -rf "$tmp"' EXIT
                ssh-keygen -q -t ed25519 -N "" -C "root@$node" -f "$tmp/key"
                age=$(ssh-to-age < "$tmp/key.pub")

                if [ -f "$file" ]; then
                  sops set "$file" "[\"$node\"]" "$(jq -Rs . < "$tmp/key")"
                else
                  jq -n --arg n "$node" --rawfile k "$tmp/key" '{($n): $k}' > "$tmp/plain.json"
                  sops encrypt --filename-override "$file" "$tmp/plain.json" > "$tmp/enc.json"
                  install -m 644 "$tmp/enc.json" "$file"
                fi
                git add "$file"

                # age = "…"; in the node's block (replace or add)
                awk -v n="$node" -v a="$age" '
                  $0 == "  " n " = {" { inblock = 1; print; next }
                  inblock && /^    age = / { print "    age = \"" a "\";"; done = 1; next }
                  inblock && $0 == "  };" { if (!done) print "    age = \"" a "\";"; inblock = 0 }
                  { print }
                ' "$nodes" > "$tmp/nodes.nix"
                cat "$tmp/nodes.nix" > "$nodes"

                nix run .#sops-config
                echo
                echo "$node: age = $age"
                echo "next: create its secrets (sops services/<svc>/secrets.enc.yaml), deploy"
              '';
            }
          );
        };
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
