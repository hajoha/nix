# Shared base for every service container on the homelab host
# (systemd-nspawn via `containers.<name>`, see modules/nixos/homelab-host.nix).
#
#   - no own Nix store / nix-daemon / GC: /nix/store is the host's (read-only)
#   - the ssh host key (= the sops age identity) is bind-mounted from the host
#   - nspawn names macvlans "mv-<parent>"; they are renamed to the VLAN name
#     ("service", "iot", ...) before networking starts, so service modules
#     use the plain interface names
{
  config,
  lib,
  pkgs,
  ...
}:
let
  hostKeyDir = "/var/lib/ssh-host-key";
  ifaces = lib.attrNames config.networking.interfaces;
in
{
  imports = [
    ../../user/root.nix
    ../../services/ssh/root.nix
    {
      # On a container restart the previous instance's macvlan (same MAC) can
      # outlive it for a moment, until the kernel has torn down its netns; until
      # then `ip link set up` fails with "Address already in use". Retry instead
      # of leaving the container without its address.
      systemd.services = lib.genAttrs (map (i: "network-addresses-${i}") ifaces) (_: {
        startLimitIntervalSec = 120;
        startLimitBurst = 30;
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = 2;
        };
      });
    }
  ];

  # Generated on the host by homelab-container-prepare; its age recipient is
  # the node's `age` in inventory/nodes.nix (`homelab-age-keys` prints it).
  services.openssh.hostKeys = [
    {
      path = "${hostKeyDir}/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];
  sops.age.sshKeyPaths = [ "${hostKeyDir}/ssh_host_ed25519_key" ];

  systemd.services.homelab-ifnames = {
    description = "Rename nspawn macvlans to their VLAN names";
    wantedBy = [
      "network-pre.target"
      "multi-user.target"
    ];
    before = [ "network-pre.target" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.iproute2 ];
    script = lib.concatMapStrings (i: ''
      if ip link show mv-${i} >/dev/null 2>&1; then
        ip link set mv-${i} down
        ip link set mv-${i} name ${i}
      fi
    '') ifaces;
  };

  # Use the nameservers from the inventory; fall back to the host's
  # resolv.conf for nodes that set `dns = null`.
  networking.useHostResolvConf = lib.mkForce (config.networking.nameservers == [ ]);
  networking.useDHCP = false;

  services.getty.autologinUser = "root";
  documentation.enable = false;
  documentation.nixos.enable = false;

  environment.systemPackages = with pkgs; [
    vim
    wget
    curl
    htop
    tcpdump
    dnsutils
  ];

  system.stateVersion = "25.11";
}
