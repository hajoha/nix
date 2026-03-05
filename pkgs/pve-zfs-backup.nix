{ pkgs, sopsFile }:

let
  # Define the datasets to backup
  backups = [
    { name = "postgres";  path = "/threetbpool/postgres"; }
    { name = "immich";    path = "/threetbpool/subvol-113-disk-0"; }
    { name = "opencloud"; path = "/threetbpool/subvol-101-disk-0"; }
  ];

  repoPath = "ssh://backup-01/./pve2";
  # Generate the Borgmatic YAML configuration
  borgmaticConfig = (pkgs.formats.yaml {}).generate "borgmatic-config.yaml" {
    location = {
      source_directories = map (b: b.path) backups;
      repositories = [ repoPath ];
      # Prevents Borg from crossing mount points outside the specified datasets
      one_file_system = true; 
    };

    storage = {
      ssh_command = "ssh";
      archive_name_format = "{hostname}-{now:%Y-%m-%d-%H%M}";
    };

    retention = {
      keep_daily = 7;
      keep_weekly = 4;
      keep_monthly = 6;
    };

    # Enables automatic ZFS snapshotting and mounts them temporarily for backup
    zfs = {};

    hooks = {
      before_backup = [ "echo 'Starting ZFS snapshot and backup process...'" ];
      after_backup = [ "echo 'Backup and retention pruning complete.'" ];
    };
  };

  # Shell script that handles SOPS decryption and runs Borgmatic
  backupScript = pkgs.writeShellScriptBin "pve-zfs-backup" ''
    set -e
    
    # 1. Setup temporary age key for SOPS decryption using host SSH key
    export TMP_KEY=$(mktemp)
    trap "rm -f $TMP_KEY" EXIT
    
    # Restrict permissions on the temp key immediately
    chmod 600 "$TMP_KEY"
    ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > "$TMP_KEY"
    export SOPS_AGE_KEY_FILE="$TMP_KEY"

    # 2. Extract the Borg passphrase
    echo "Decrypting BORG_PASSPHRASE..."
    export BORG_PASSPHRASE=$(${pkgs.sops}/bin/sops -d --extract '["borg_passphrase"]' ${sopsFile})

    # 3. Execute Borgmatic
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

  # Systemd Timer Definition (Daily at 3:00 AM)
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
    # Create the directory structure for systemd units
    mkdir -p $out/etc/systemd/system
    cp ${serviceUnit} $out/etc/systemd/system/pve-zfs-backup.service
    cp ${timerUnit} $out/etc/systemd/system/pve-zfs-backup.timer

    # Create an easy installation script
    mkdir -p $out/bin
    cat <<EOF > $out/bin/pve-zfs-backup-install
#!/bin/bash
if [[ \$EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

echo "Linking systemd units from Nix store..."
ln -sf $out/etc/systemd/system/pve-zfs-backup.service /etc/systemd/system/
ln -sf $out/etc/systemd/system/pve-zfs-backup.timer /etc/systemd/system/

systemctl daemon-reload
systemctl enable --now pve-zfs-backup.timer

echo "Installation complete."
echo "Trigger manual backup: pve-zfs-backup"
echo "Check timer status: systemctl list-timers | grep pve"
EOF
    chmod +x $out/bin/pve-zfs-backup-install
  '';
}