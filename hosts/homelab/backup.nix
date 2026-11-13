# Off-site backup with borgmatic to the Hetzner storage box. The `zfs` hook
# snapshots the datasets behind source_directories, so the backup is
# consistent without stopping the containers.
#
#   systemctl start borgmatic          run now
#   borgmatic list / borgmatic info
{
  config,
  pkgs,
  ...
}:
let
  containerDir = name: "/var/lib/nixos-containers/${name}";
in
{
  sops.secrets.borg_passphrase = {
    sopsFile = ./secrets.enc.yaml;
  };

  # Hetzner storage box. Logs in with the host's ssh key, whose public part
  # (/etc/ssh/ssh_host_ed25519_key.pub) is added to the box in the Hetzner
  # console (SSH keys).
  programs.ssh.extraConfig = ''
    Host backup-01
      HostName u557074.your-storagebox.de
      User u557074
      Port 23
      IdentityFile /etc/ssh/ssh_host_ed25519_key
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new
  '';

  services.borgmatic = {
    enable = true;
    settings = {
      # The container roots and their ssh keys (on the unredundant NVMe;
      # one_file_system: without the ZFS data mounts inside them) and the
      # data datasets, listed separately.
      source_directories = [
        "/var/lib/nixos-containers"
        "/var/lib/homelab/keys"
        "${containerDir "nix-postgres"}/var/lib/postgresql"
        "${containerDir "nix-immich"}/var/lib/immich"
        "${containerDir "nix-opencloud"}/var/lib/opencloud/data"
      ];
      repositories = [
        {
          path = "ssh://backup-01/./pve2"; # repository name from the old host
          label = "backup-01";
        }
      ];
      encryption_passcommand = "cat ${config.sops.secrets.borg_passphrase.path}";
      archive_name_format = "{hostname}-{now:%Y-%m-%d-%H%M}";
      # Older archives are named pve2-…: list and prune all of them as one
      # series, not only the ones matching the current hostname.
      match_archives = "*";
      compression = "lz4";
      one_file_system = true;
      zfs = {
        zfs_command = "${config.boot.zfs.package}/bin/zfs";
        mount_command = "${pkgs.util-linux}/bin/mount";
        umount_command = "${pkgs.util-linux}/bin/umount";
      };

      keep_daily = 7;
      keep_weekly = 4;
      keep_monthly = 6;
    };
  };

  # The upstream unit is sandboxed for plain file backups. The zfs hook needs
  # /dev/zfs (snapshots) and CAP_SYS_ADMIN to mount them under
  # /run/borgmatic (in the unit's own mount namespace). Drop-in: the
  # capability is added to the upstream set.
  systemd.services.borgmatic.serviceConfig = {
    PrivateDevices = false;
    CapabilityBoundingSet = [ "CAP_SYS_ADMIN" ];
  };

  # Same schedule as before (03:00 + up to 30 min).
  systemd.timers.borgmatic.timerConfig = {
    OnCalendar = "03:00:00";
    RandomizedDelaySec = "30min";
    Persistent = true;
  };
}
