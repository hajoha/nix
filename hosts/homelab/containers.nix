# Host-specific extras for individual containers: devices and capabilities.
# Everything else about a container comes from the inventory
# (modules/nixos/homelab-host.nix). Large data (immich library, arr media,
# postgres, ./data-volumes.nix) is a ZFS dataset on the HDD pool mounted
# inside the container root, e.g. <pool>/containers/nix-arr/data -> /data,
# so it needs no bind mount here.
{
  lib,
  pkgs,
  params,
  ...
}:
let
  dataVolumes = import ./data-volumes.nix;

  dri = {
    allowedDevices = [
      {
        node = "/dev/dri/renderD128";
        modifier = "rw";
      }
    ];
    bindMounts."/dev/dri" = {
      hostPath = "/dev/dri";
      isReadOnly = false;
    };
  };
in
{
  hardware.graphics = {
    enable = params.gpu != null;
    extraPackages = lib.optionals (params.gpu == "intel") [
      pkgs.intel-media-driver # VA-API / QSV for Skylake (P530)
    ];
  };

  # The pool is unlocked by hand after boot. A container whose data dataset is
  # not mounted must not start: it would initialise an empty postgres/immich
  # on the NVMe underneath the mount point.
  systemd.services = lib.mapAttrs' (
    node: vols:
    lib.nameValuePair "container@${node}" {
      after = [ "zfs-mount.service" ];
      preStart = lib.mkBefore (
        lib.concatMapStrings (p: ''
          ${pkgs.util-linux}/bin/mountpoint -q /var/lib/nixos-containers/${node}${p} || {
            echo "${p}: ZFS dataset not mounted (pool locked? zfs load-key ${params.pool} && zfs mount -a)" >&2
            exit 1
          }
        '') (lib.attrNames vols)
      );
    }
  ) dataVolumes;

  containers = {
    # Thread/Zigbee radio + the wpan0 tun device of the OpenThread border
    # router (enableTun also grants CAP_NET_ADMIN).
    nix-homeassistant = {
      enableTun = true;
      allowedDevices = [
        {
          node = "char-ttyUSB";
          modifier = "rw";
        }
        {
          node = "char-ttyACM";
          modifier = "rw";
        }
      ];
      bindMounts.${params.radio} = {
        hostPath = params.radio;
        isReadOnly = false;
      };
    };

    nix-immich = lib.mkIf (params.gpu != null) dri;

    # nixarr: WireGuard network namespace (VPN confinement) and podman
    # containers inside the container. Needs broad privileges; if it misbehaves
    # this is the candidate for a microvm instead.
    nix-arr = lib.mkMerge [
      {
        enableTun = true;
        additionalCapabilities = [ "all" ];
        extraFlags = [
          "--system-call-filter=@keyring"
          "--system-call-filter=bpf"
        ];
        allowedDevices = [
          {
            node = "/dev/fuse";
            modifier = "rwm";
          }
        ];
        bindMounts."/dev/fuse" = {
          hostPath = "/dev/fuse";
          isReadOnly = false;
        };
      }
      (lib.mkIf (params.gpu != null) dri)
    ];
  };
}
