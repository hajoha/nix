{ pkgs, sopsFile }:

let
  # Define the datasets to backup
  backups = [
    { name = "postgres";  path = "/threetbpool/postgres"; }
    { name = "immich";    path = "/threetbpool/subvol-113-disk-0"; }
    { name = "opencloud"; path = "/threetbpool/subvol-101-disk-0"; }
  ];

  # Repository URL using your SSH alias from .ssh/config
  # The /./ is a Borg convention to indicate an absolute path on the remote
  repoPath = "ssh://backup-01/./home/pve2";

  # Generate the Borgmatic YAML configuration
  borgmaticConfig = (pkgs.formats.yaml {}).generate "borgmatic-config.yaml" {
    location = {
      source_directories = map (b: b.path) backups;
      repositories = [ repoPath ];
      # Required to allow Borgmatic to step into the ZFS snapshots it creates
      extra_borders = [ "zfs" ];
    };

    storage = {
      # Uses the 'ssh' alias defined in /root/.ssh/config
      ssh_command = "ssh";
      archive_name_format = "{hostname}-{now:%Y-%m-%d-%H%M}";
    };

    retention = {
      keep_daily = 7;
      keep_weekly = 4;
      keep_monthly = 6;
    };

    # This section enables automatic ZFS snapshotting during the backup process
    zfs = {
      # Borgmatic will automatically detect the datasets for your source_directories
    };

    hooks = {
      before_backup = [ "echo 'Starting ZFS snapshot and backup process...'" ];
      after_backup = [ "echo 'Backup and retention pruning complete.'" ];
    };
  };

  # The shell script that handles SOPS decryption and runs Borgmatic
  backupScript = pkgs.writeShellScriptBin "pve-zfs-backup" ''
    set -e
    
    # 1. Setup temporary age key for SOPS decryption using host SSH key
    export TMP_KEY=$(mktemp)
    trap "rm -f $TMP_KEY" EXIT
    ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > "$TMP_KEY"
    export SOPS_AGE_KEY_FILE="$TMP_KEY"

    # 2. Extract the Borg passphrase from your encrypted SOPS file
    echo "Decrypting BORG_PASSPHRASE..."
    export BORG_PASSPHRASE=$(${pkgs.sops}/bin/sops -d --extract '["borg_passphrase"]' ${sopsFile})

    # 3. Execute Borgmatic with the generated config
    echo "Executing Borgmatic backup to Hetzner Storage Box..."
    ${pkgs.borgmatic}/bin/borgmatic --config ${borgmaticConfig} \
      --verbosity 1 --stats "$@"
  '';

  # Systemd Service Definition
  serviceUnit = pkgs.writeText "pve-zfs-backup.service" ''
    [Unit]
    Description=Borgmatic ZFS Backup
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=oneshot
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

    # Create an easy installation script to link the units into /etc
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
echo "Installation complete. You can trigger a manual backup with: pve-zfs-backup"
EOF
    chmod +x $out/bin/pve-zfs-backup-install
  '';
}