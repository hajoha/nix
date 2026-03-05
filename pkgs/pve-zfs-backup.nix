{ pkgs, sopsFile }:

let
  backups = [
    { name = "postgres";  path = "/threetbpool/postgres"; }
    { name = "immich";    path = "/threetbpool/subvol-113-disk-0"; }
    { name = "opencloud"; path = "/threetbpool/subvol-101-disk-0"; }
  ];

  # Define the repository path once to keep it DRY
  repoPath = "ssh://backup-01:/home/pve2";

  borgmaticConfig = (pkgs.formats.yaml {}).generate "borgmatic-config.yaml" {
    location = {
      source_directories = map (b: b.path) backups;
      repositories = [ repoPath ];
      # FIX: Moved from hooks to location
      extra_backup_borders = [ "zfs" ];
    };

    storage = {
      ssh_command = "ssh backup-01";
      archive_name_format = "{hostname}-{now:%Y-%m-%d-%H%M}";
    };

    retention = {
      keep_daily = 7;
      keep_weekly = 4;
      keep_monthly = 6;
    };

    hooks = {
      # This runs before any backup starts
      before_backup = [
        "echo 'Starting ZFS snapshot and backup process...'"
      ];
      # This runs after everything is finished
      after_backup = [
        "echo 'Backup and retention pruning complete.'"
      ];
    };
  };

  backupScript = pkgs.writeShellScriptBin "pve-zfs-backup" ''
    set -e
    
    # 1. Setup temporary age key for SOPS
    TMP_KEY=$(mktemp)
    trap "rm -f $TMP_KEY" EXIT
    ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > "$TMP_KEY"
    export SOPS_AGE_KEY_FILE="$TMP_KEY"

    # 2. Extract secrets
    echo "Decrypting backup secrets..."
    export BORG_PASSPHRASE=$(${pkgs.sops}/bin/sops -d --extract '["borg_passphrase"]' ${sopsFile})

    # 3. Define Repo Path (needed for the --repository flag below)
    REPO_PATH="${repoPath}"

    # 4. Verify ZFS paths
    for path in ${builtins.concatStringsSep " " (map (b: b.path) backups)}; do
      if [ ! -d "$path" ]; then
        echo "Warning: Path $path not found. Skipping validation..."
      fi
    done

    # 5. Execute Borgmatic
    # Note: With 'extra_backup_borders: [zfs]', Borgmatic will automatically 
    # create, mount, and destroy snapshots for each source_directory.
    echo "Starting backup to Hetzner Storage Box..."
    ${pkgs.borgmatic}/bin/borgmatic --config ${borgmaticConfig} \
      --verbosity 1 --stats "$@"
  '';

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
  name = "pve-zfs-backup";
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
    echo "Installing systemd units from Nix store..."
    ln -sf $out/etc/systemd/system/pve-zfs-backup.service /etc/systemd/system/
    ln -sf $out/etc/systemd/system/pve-zfs-backup.timer /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable pve-zfs-backup.timer
    systemctl start pve-zfs-backup.timer
    echo "Installation complete. Backup timer is active."
    EOF
    chmod +x $out/bin/pve-zfs-backup-install
  '';
}