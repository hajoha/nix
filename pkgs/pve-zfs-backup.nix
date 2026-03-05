{ pkgs, sopsFile }:

let
  # Define the datasets to backup
  backups = [
    { name = "postgres";  path = "/threetbpool/postgres"; }
    { name = "immich";    path = "/threetbpool/subvol-113-disk-0"; }
    { name = "opencloud"; path = "/threetbpool/subvol-101-disk-0"; }
  ];

  repoPath = "ssh://backup-01/./pve2";

  # Generate the Borgmatic YAML configuration (Modernized Flat Schema)
  borgmaticConfig = (pkgs.formats.yaml {}).generate "borgmatic-config.yaml" {
    # --- Source and Repositories ---
    source_directories = map (b: b.path) backups;
    repositories = [ { path = repoPath; } ];

    # --- Storage and Performance ---
    one_file_system = true;
    ssh_command = "ssh";
    archive_name_format = "{hostname}-{now:%Y-%m-%d-%H%M}";
    
    # --- Retention Policy ---
    keep_daily = 7;
    keep_weekly = 4;
    keep_monthly = 6;

    # --- ZFS Configuration ---
    zfs = {};

    # --- THE CRITICAL FIXES ---
    # 1. Prevents the "Runtime directory overlaps" error
    exclude_runtime_directory = false;
    
    # 2. Modern Hooks (using 'commands' scope)
    before_everything = [ "echo 'Starting ZFS snapshot and backup process...'" ];
    after_everything = [ "echo 'Backup and retention pruning complete.'" ];
  };

  # Shell script with SOPS decryption and aggressive cleanup
  backupScript = pkgs.writeShellScriptBin "pve-zfs-backup" ''
    set -e
    
    # Define cleanup function to handle crashes/interrupts
    cleanup() {
      echo "--- Post-execution cleanup ---"
      # Release SOPS key
      [[ -f "$TMP_KEY" ]] && rm -f "$TMP_KEY"
      
      # Unmount any stubborn Borgmatic ZFS snapshots still in /proc/mounts
      # This prevents the "Dataset is busy" error on subsequent runs
      grep "borgmatic" /proc/mounts | cut -d' ' -f2 | xargs -r umount -f || true
      echo "Cleanup complete."
    }

    # Set the trap
    export TMP_KEY=$(mktemp)
    trap cleanup EXIT
    
    chmod 600 "$TMP_KEY"
    ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > "$TMP_KEY"
    export SOPS_AGE_KEY_FILE="$TMP_KEY"

    echo "Decrypting BORG_PASSPHRASE..."
    export BORG_PASSPHRASE=$(${pkgs.sops}/bin/sops -d --extract '["borg_passphrase"]' ${sopsFile})

    echo "Executing Borgmatic backup..."
    ${pkgs.borgmatic}/bin/borgmatic --config ${borgmaticConfig} --verbosity 1 --stats "$@"
  '';

  # Systemd Service Definition
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

  # Systemd Timer Definition
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
if [[ \$EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

ln -sf $out/etc/systemd/system/pve-zfs-backup.service /etc/systemd/system/
ln -sf $out/etc/systemd/system/pve-zfs-backup.timer /etc/systemd/system/

systemctl daemon-reload
systemctl enable --now pve-zfs-backup.timer
echo "Installation complete."
EOF
    chmod +x $out/bin/pve-zfs-backup-install
  '';
}