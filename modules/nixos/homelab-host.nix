# Turns every inventory node with a `service` into a NixOS container
# (`containers.<name>`, systemd-nspawn) on this host.
#
# Per container:
#   - its own ZFS dataset <pool>/containers/<name>, mounted as the container
#     root (/var/lib/nixos-containers/<name>); created on first start
#   - an ssh host key in /var/lib/homelab/keys/<name> (dataset
#     <pool>/homelab-keys; generated if missing, or copied over from the old
#     LXC so sops keeps working)
#   - one macvlan per VLAN interface the node uses (on the host VLAN
#     interface of the same name), see container-base.nix
#
# Hardware and host-specific extras (devices, capabilities, data binds) are
# plain `containers.<name>.*` definitions in hosts/homelab/containers.nix.
#
#   nixos-container root-login nix-paperless     shell inside
#   systemctl restart container@nix-paperless
#   journalctl -M nix-paperless -u paperless-web
{
  config,
  lib,
  pkgs,
  inputs,
  self,
  inventory,
  params,
  ...
}:
let
  inherit (lib)
    mapAttrs
    mapAttrs'
    nameValuePair
    filterAttrs
    attrNames
    unique
    concatMap
    concatMapStrings
    ;

  pool = params.pool;
  keyRoot = "/var/lib/homelab/keys";

  serviceNodes = filterAttrs (_: n: n.service != null) inventory.nodes;

  # Flake modules a service needs on top of the shared base.
  extraModules = {
    nix-arr = [ inputs.nixarr.nixosModules.default ];
    nix-tranquil = [ inputs.tranquil.nixosModules.default ];
  };

  vlansOf = node: attrNames (node.networking.interfaces or { });
  usedVlans = unique (concatMap vlansOf (lib.attrValues serviceNodes));

  mkContainer = name: node: {
    autoStart = node.autoStart;
    privateNetwork = true;
    macvlans = vlansOf node;
    specialArgs = { inherit inputs self; };

    bindMounts."/var/lib/ssh-host-key" = {
      hostPath = "${keyRoot}/${name}";
      isReadOnly = true;
    };

    config = {
      imports = [
        ./homelab.nix
        inventory.homelabConfig
        ./container-base.nix
        ../../services/alloy/default.nix
        ../../services/${node.service}/default.nix
        inputs.sops-nix.nixosModules.sops
        {
          networking = node.networking // {
            hostName = name;
          };
          # same version label as the host (containers are evaluated
          # without the flake's nixpkgs revision otherwise)
          system.nixos = {
            inherit (config.system.nixos) versionSuffix revision;
          };
        }
      ]
      ++ (extraModules.${name} or [ ]);
    };
  };
in
{
  assertions = map (v: {
    assertion = params.vlans ? ${v};
    message = "hosts/homelab/params.nix: no VLAN id for interface `${v}` (used by a container)";
  }) usedVlans;

  containers = mapAttrs mkContainer serviceNodes;

  # One host VLAN interface per network, without an address; containers hang
  # macvlans off it.
  networking.vlans = lib.genAttrs usedVlans (v: {
    id = params.vlans.${v};
    interface = params.trunk;
  });
  networking.interfaces = lib.genAttrs usedVlans (_: { });

  # Dataset + host key for every container, before it starts.
  systemd.services = {
    homelab-container-prepare = {
      description = "Create container datasets and ssh host keys";
      after = [ "zfs-mount.service" ];
      requires = [ "zfs-mount.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [
        config.boot.zfs.package
        pkgs.openssh
      ];
      script = ''
        if ! zfs list -H -o name ${pool}/homelab-keys >/dev/null 2>&1; then
          zfs create -o mountpoint=${keyRoot} ${pool}/homelab-keys
        fi
        chmod 700 ${keyRoot}
      ''
      + concatMapStrings (name: ''
        ds=${pool}/containers/${name}
        if ! zfs list -H -o name "$ds" >/dev/null 2>&1; then
          echo "creating $ds"
          zfs create -p -o mountpoint=/var/lib/nixos-containers/${name} "$ds"
        fi
        key=${keyRoot}/${name}/ssh_host_ed25519_key
        if [ ! -e "$key" ]; then
          echo "generating ssh host key for ${name}"
          install -d -m 700 ${keyRoot}/${name}
          ssh-keygen -q -t ed25519 -N "" -C "root@${name}" -f "$key"
        fi
      '') (attrNames serviceNodes);
    };
  }
  // mapAttrs' (
    name: _:
    nameValuePair "container@${name}" {
      after = [ "homelab-container-prepare.service" ];
      requires = [ "homelab-container-prepare.service" ];
    }
  ) serviceNodes;

  # Local snapshots of every container root (sanoid prunes them).
  services.sanoid = {
    enable = true;
    datasets."${pool}/containers" = {
      recursive = true;
      autosnap = true;
      autoprune = true;
      hourly = 24;
      daily = 14;
      monthly = 3;
    };
    # 1.7 TB of media with constant download churn: daily only, short.
    datasets."${pool}/containers/nix-arr/data" = {
      autosnap = true;
      autoprune = true;
      hourly = 0;
      daily = 3;
      monthly = 0;
    };
  };
}
