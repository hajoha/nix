{ pkgs, sopsFile }:

let
  backups = [
    { name = "postgres";  path = "/threetbpool/postgres"; }
    { name = "immich";    path = "/threetbpool/subvol-113-disk-0"; }
    { name = "opencloud"; path = "/threetbpool/subvol-101-disk-0"; }
    { name = "proxmox-etc"; path = "/etc/pve"; }
  ];

  borgmaticConfig = (pkgs.formats.yaml {}).generate "borgmatic-config.yaml" {
    source_directories = map (b: b.path) backups;
    
    # We remove the hardcoded repositories list here because 
    # we will pass it via the CLI at runtime.
    
    storage = {
      encryption = "repokey-blake2";
      ssh_command = "ssh -p 23 -i /root/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new";
      archive_name_format = "{hostname}-{now:%Y-%m-%d-%H%M}"; 
    };

    zfs.enabled = true;

    retention = {
      keep_daily = 7;
      keep_weekly = 4;
      keep_monthly = 6;
    };
  };

  backupScript = pkgs.writeShellScriptBin "pve-zfs-backup" ''
    set -e
    
    # 1. Extract both secrets from SOPS
    export BORG_PASSPHRASE=$(${pkgs.sops}/bin/sops -d --extract '["borg_passphrase"]' ${sopsFile})
    REPO_PATH=$(${pkgs.sops}/bin/sops -d --extract '["repo_path"]' ${sopsFile})

    # 2. Verify ZFS paths
    for path in ${builtins.concatStringsSep " " (map (b: b.path) backups)}; do
      if [ ! -d "$path" ]; then
        echo "Warning: Path $path not found. Skipping validation..."
      fi
    done

    # 3. Execute Borgmatic, overriding the repository path with the secret
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