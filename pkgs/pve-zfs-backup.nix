{ pkgs, sopsFile }:

let
  backups = [
    { name = "postgres";  path = "/threetbpool/postgres"; }
    { name = "immich";    path = "/threetbpool/subvol-113-disk-0"; }
    { name = "opencloud"; path = "/threetbpool/subvol-101-disk-0"; }
  ];

  repoPath = "ssh://backup-01/./pve2";

  borgmaticConfig = (pkgs.formats.yaml {}).generate "borgmatic-config.yaml" {
      # --- Source Directories (Top Level) ---
      source_directories = map (b: b.path) backups;
      one_file_system = true;
  
      # --- Storage Section (The new Nested way) ---
      storage = {
        repositories = [ { path = repoPath; } ];
        ssh_command = "ssh";
        archive_name_format = "{hostname}-{now:%Y-%m-%d-%H%M}";
        compression = "lz4";
        # This is the "Critical Fix" from before, moved to its correct home
        unsafe_skip_path_validation_before_create = true;
      };
  
      # --- Retention Section (The new Nested way) ---
      retention = {
        keep_daily = 7;
        keep_weekly = 4;
        keep_monthly = 6;
      };
  
      # --- ZFS Section ---
      zfs = {};
  
      # --- Hooks Section ---
      # Note: Using the modern 'commands' syntax instead of deprecated hooks
      hooks = {
        commands = [
          {
            before = "everything";
            run = [ "echo 'Starting ZFS snapshot and backup process...'" ];
          }
          {
            after = "everything";
            run = [ "echo 'Backup and retention pruning complete.'" ];
          }
        ];
      };
    };
  backupScript = pkgs.writeShellScriptBin "pve-zfs-backup" ''
    set -e
    
    # Aggressive cleanup trap for Proxmox/ZFS
    cleanup() {
      echo "--- Post-execution cleanup ---"
      [[ -f "$TMP_KEY" ]] && rm -f "$TMP_KEY"
      
      # Use the grep method to find and unmount anything borgmatic left behind
      if grep -q "borgmatic" /proc/mounts; then
          echo "Found lingering ZFS mounts. Force unmounting..."
          grep "borgmatic" /proc/mounts | cut -d' ' -f2 | xargs -r umount -f || true
      fi
    }

    export TMP_KEY=$(mktemp)
    trap cleanup EXIT
    
    chmod 600 "$TMP_KEY"
    ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > "$TMP_KEY"
    export SOPS_AGE_KEY_FILE="$TMP_KEY"

    echo "Decrypting BORG_PASSPHRASE..."
    export BORG_PASSPHRASE=$(${pkgs.sops}/bin/sops -d --extract '["borg_passphrase"]' ${sopsFile})

    echo "Executing Borgmatic..."
    ${pkgs.borgmatic}/bin/borgmatic --config ${borgmaticConfig} --verbosity 1 --stats "$@"
  '';

  # Systemd definitions remain the same...
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
    Group=root
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