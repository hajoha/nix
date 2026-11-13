# Off-site backup with borgmatic (replaces pkgs/pve-zfs-backup.nix, which was
# installed by hand on Proxmox). Same borg repository and passphrase; the
# `zfs` hook snapshots the datasets behind source_directories, so the backup
# is consistent without stopping the containers.
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
    sopsFile = ../../secrets/pve2.enc.yaml;
  };

  # Hetzner storage box. New key on the host, authorised once (README):
  #   ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519_hetzner
  programs.ssh.extraConfig = ''
    Host backup-01
      HostName u557074.your-storagebox.de
      User u557074
      Port 23
      IdentityFile /root/.ssh/id_ed25519_hetzner
      StrictHostKeyChecking accept-new
  '';

  services.borgmatic = {
    enable = true;
    settings = {
      # Same data as the old Proxmox backup (postgres, immich, opencloud),
      # plus the container roots and their ssh keys, which live on the
      # unredundant NVMe now (one_file_system: the roots without the ZFS
      # data mounts inside them, those are listed separately).
      source_directories = [
        "/var/lib/nixos-containers"
        "/var/lib/homelab/keys"
        "${containerDir "nix-postgres"}/var/lib/postgresql"
        "${containerDir "nix-immich"}/var/lib/immich"
        "${containerDir "nix-opencloud"}/var/lib/opencloud/data"
      ];
      repositories = [
        {
          path = "ssh://backup-01/./pve2";
          label = "backup-01";
        }
      ];
      encryption_passcommand = "cat ${config.sops.secrets.borg_passphrase.path}";
      archive_name_format = "{hostname}-{now:%Y-%m-%d-%H%M}";
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

  # Same schedule as before (03:00 + up to 30 min).
  systemd.timers.borgmatic.timerConfig = {
    OnCalendar = "03:00:00";
    RandomizedDelaySec = "30min";
    Persistent = true;
  };
}
