{ pkgs, sopsFile }:

let
  # configuration constants
  repoPath = "ssh://backup-01/./pve2";
  
  # The actual Borgmatic Config (Declarative)
  borgmaticConfig = (pkgs.formats.yaml {}).generate "config.yaml" {
    source_directories = [
      "/threetbpool/postgres"
      "/threetbpool/subvol-113-disk-0"
      "/threetbpool/subvol-101-disk-0"
    ];
    repositories = [ { path = repoPath; } ];
    one_file_system = true;
    unsafe_skip_path_validation_before_create = true;
    
    # Retention
    keep_daily = 7;
    keep_weekly = 4;
    keep_monthly = 6;

    # ZFS Magic
    zfs = {};

    # Consistency checks (Important for long-term backups)
    consistency = {
      checks = [ { name = "repository"; } { name = "archives"; } ];
      check_last = 3;
    };
  };

  # The Execution Script
  # We use 'writeShellScript' so Nix handles the shebang and pathing
  backupExec = pkgs.writeShellScript "run-borgmatic" ''
    set -euo pipefail

    # Setup cleanup trap
    cleanup() {
      echo "Cleaning up ZFS mounts..."
      grep "borgmatic" /proc/mounts | cut -d' ' -f2 | xargs -r umount -f || true
    }
    trap cleanup EXIT

    # Decrypt passphrase to a temp env var (only exists in this process memory)
    export BORG_PASSPHRASE=$(${pkgs.sops}/bin/sops -d --extract '["borg_passphrase"]' ${sopsFile})
    
    # Run borgmatic
    ${pkgs.borgmatic}/bin/borgmatic --config ${borgmaticConfig} --verbosity 1 --stats
  '';

in pkgs.stdenv.mkDerivation {
  name = "pve-backup-bundle";
  phases = [ "installPhase" ];
  
  installPhase = ''
    mkdir -p $out/bin $out/lib/systemd/system
    
    # The main command
    ln -s ${backupExec} $out/bin/pve-zfs-backup

    # The Service
    cat <<EOF > $out/lib/systemd/system/pve-zfs-backup.service
[Unit]
Description=Borgmatic ZFS Backup
After=network-online.target

[Service]
Type=oneshot
# Use a private temporary directory for the service
PrivateTmp=true
# Protect the rest of the system
ProtectSystem=strict
ReadWritePaths=/threetbpool /run/user/0/borgmatic
ExecStart=$out/bin/pve-zfs-backup
EOF

    # The Timer
    cat <<EOF > $out/lib/systemd/system/pve-zfs-backup.timer
[Unit]
Description=Daily PVE ZFS Backup Timer

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF
  '';
}