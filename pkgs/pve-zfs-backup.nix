{ pkgs, sopsFile }:

let
  zfsPoolBase = "/threetbpool";
  mountRoot = "${zfsPoolBase}/borg_mounts";

  backups = [
    { name = "postgres";  dataset = "threetbpool/postgres";            mount = "${mountRoot}/postgres"; }
    { name = "immich";    dataset = "threetbpool/subvol-113-disk-0";  mount = "${mountRoot}/immich"; }
    { name = "opencloud"; dataset = "threetbpool/subvol-101-disk-0";  mount = "${mountRoot}/opencloud"; }
  ];

  repoPath = "ssh://backup-01/./pve2";

  borgmaticConfig = (pkgs.formats.yaml {}).generate "borgmatic-config.yaml" {
    source_directories = map (b: b.mount) backups;

    storage = {
      repositories = [ { path = repoPath; } ];
      ssh_command = "ssh";
      archive_name_format = "{hostname}-{now:%Y-%m-%d-%H%M}";
      compression = "lz4";
      # Ensure it stays within the mount points
      one_file_system = true;
    };

    retention = {
      keep_daily = 7;
      keep_weekly = 4;
      keep_monthly = 6;
    };

    # REMOVED: zfs = {}; 
    # By removing the zfs key entirely, Borgmatic won't try to run its 
    # internal ZFS hook, which stops the "No ZFS datasets found" error.

    hooks = {
      before_everything = [ "echo 'Starting Borgmatic backup using ZFS-hosted mount points...'" ];
      after_everything = [ "echo 'Backup and retention pruning complete.'" ];
    };
  };

  backupScript = pkgs.writeShellScriptBin "pve-zfs-backup" ''
    set -e
    
    cleanup() {
      echo "--- Post-execution cleanup ---"
      [[ -f "$TMP_KEY" ]] && rm -f "$TMP_KEY"
      
      for item in ${builtins.concatStringsSep " " (map (b: "'${b.name}'") (pkgs.lib.reverseList backups))}; do
         target_mnt="${mountRoot}/$item"
         if ${pkgs.util-linux}/bin/mountpoint -q "$target_mnt"; then
            echo "Unmounting $target_mnt..."
            ${pkgs.util-linux}/bin/umount -l "$target_mnt" || true
         fi
      done

      for ds in ${builtins.concatStringsSep " " (map (b: "'${b.dataset}'") backups)}; do
         ${pkgs.zfs}/bin/zfs destroy -r "$ds@backup-snap" 2>/dev/null || true
      done

      rmdir "${mountRoot}" 2>/dev/null || true
    }

    trap cleanup EXIT

    export TMP_KEY=$(mktemp)
    chmod 600 "$TMP_KEY"
    ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > "$TMP_KEY"
    export SOPS_AGE_KEY_FILE="$TMP_KEY"

    echo "Decrypting BORG_PASSPHRASE..."
    export BORG_PASSPHRASE=$(${pkgs.sops}/bin/sops -d --extract '["borg_passphrase"]' ${sopsFile})

    echo "Creating snapshots and mounting to ${mountRoot}..."
    mkdir -p "${mountRoot}"
    
    ${builtins.concatStringsSep "\n" (map (b: ''
      echo "Snapshotting ${b.dataset}..."
      ${pkgs.zfs}/bin/zfs snapshot "${b.dataset}@backup-snap"
      mkdir -p "${b.mount}"
      ${pkgs.util-linux}/bin/mount -t zfs "${b.dataset}@backup-snap" "${b.mount}"
    '') backups)}

    echo "Executing Borgmatic..."
    ${pkgs.borgmatic}/bin/borgmatic --config ${borgmaticConfig} --verbosity 1 --stats "$@"
  '';

  serviceUnit = pkgs.writeText "pve-zfs-backup.service" ''
    [Unit]
    Description=Borgmatic ZFS Backup
    After=network-online.target
    Wants=network-online.target
    [Service]
    Type=oneshot
    Environment="HOME=/root"
    ExecStart=${backupScript}/bin/pve-zfs-backup
    User=root
  '';

  timerUnit = pkgs.writeText "pve-zfs-backup.timer" ''
    [Unit]
    Description=Daily PVE ZFS Backup Timer
    [Timer]
    OnCalendar=03:00:00
    RandomizedDelaySec=30min
    Persistent=true
    [Install]
    WantedBy=timers.target
  '';

in
pkgs.symlinkJoin {
  name = "pve-zfs-backup-tool";
  paths = [ backupScript ];
  postBuild = ''
    mkdir -p $out/etc/systemd/system
    cp ${serviceUnit} $out/etc/systemd/system/pve-zfs-backup.service
    cp ${timerUnit} $out/etc/systemd/system/pve-zfs-backup.timer
    mkdir -p $out/bin
    cat <<EOF > $out/bin/pve-zfs-backup-install
#!/bin/bash
ln -sf $out/etc/systemd/system/pve-zfs-backup.service /etc/systemd/system/
ln -sf $out/etc/systemd/system/pve-zfs-backup.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now pve-zfs-backup.timer
EOF
    chmod +x $out/bin/pve-zfs-backup-install
  '';
}