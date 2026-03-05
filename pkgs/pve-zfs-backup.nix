{ pkgs, sopsFile }:

let
  backups = [
    { name = "postgres";  path = "/threetbpool/postgres"; }
    { name = "immich";    path = "/threetbpool/subvol-113-disk-0"; }
    { name = "opencloud"; path = "/threetbpool/subvol-101-disk-0"; }
    # { name = "proxmox-etc"; path = "/etc/pve"; }
  ];

  borgmaticConfig = (pkgs.formats.yaml {}).generate "borgmatic-config.yaml" {
      # 1. Location block: Handles WHERE and WHAT
      location = {
        source_directories = map (b: b.path) backups;
        repositories = [ "ssh://backup-01:/home/pve2/" ]; # Must match what's in SOPS
      };
  
      # 2. Storage block: Handles HOW
      storage = {
        # encryption_passphrase is not needed here as BORG_PASSPHRASE env var is used
        ssh_command = "ssh backup-01";
        archive_name_format = "{hostname}-{now:%Y-%m-%d-%H%M}";
      };
  
      # 3. Retention block: Handles HOW LONG
      retention = {
        keep_daily = 7;
        keep_weekly = 4;
        keep_monthly = 6;
      };
  
      # 4. Hooks block: Handles SPECIAL ACTIONS (like ZFS)
      hooks = {
        # This must be under hooks, not at the top level
        extra_backup_borders = [ "zfs" ];
      };
    };

  backupScript = pkgs.writeShellScriptBin "pve-zfs-backup" ''
    set -e
    
    # 1. Generate age key from SSH host key on the fly
    # We use a temporary file to keep the decrypted age key out of the Nix store
    TMP_KEY=$(mktemp)
    trap "rm -f $TMP_KEY" EXIT
    
    # Convert private SSH key to age format
    ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > "$TMP_KEY"
    export SOPS_AGE_KEY_FILE="$TMP_KEY"

    # 2. Extract secrets from SOPS
    echo "Decrypting backup secrets..."
    export BORG_PASSPHRASE=$(${pkgs.sops}/bin/sops -d --extract '["borg_passphrase"]' ${sopsFile})
    REPO_PATH=$(${pkgs.sops}/bin/sops -d --extract '["repo_path"]' ${sopsFile})

    # 3. Verify ZFS paths
    for path in ${builtins.concatStringsSep " " (map (b: b.path) backups)}; do
      if [ ! -d "$path" ]; then
        echo "Warning: Path $path not found. Skipping validation..."
      fi
    done

    # 4. Execute Borgmatic
    echo "Starting backup to Hetzner Storage Box..."
    ${pkgs.borgmatic}/bin/borgmatic --config ${borgmaticConfig} \
      --repository "$REPO_PATH" \
      --verbosity 1 --stats "$@"
  '';

  serviceUnit = pkgs.writeText "pve-zfs-backup.service" ''
    [Unit]
    Description=Borgmatic ZFS Backup
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=oneshot
    # Run as root to access /etc/ssh/ssh_host_ed25519_key
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