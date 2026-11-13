# The homelab server: NixOS on bare metal (replaces Proxmox on pve2).
# Every service runs as a NixOS container generated from the inventory
# (modules/nixos/homelab-host.nix); this file is the host itself.
{
  pkgs,
  params,
  ...
}:
{
  imports = [
    ./hardware.nix
    ./network.nix
    ./containers.nix
    ./backup.nix
    ../../modules/nixos/homelab-host.nix
    ../../services/build/default.nix
    ../../user/root.nix
    ../../services/ssh/root.nix
  ];

  networking.hostName = params.hostName;
  networking.hostId = params.hostId;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 10;

  # --- ZFS (data pool on the HDDs) ---
  boot.supportedFilesystems.zfs = true;
  boot.zfs.extraPools = [ params.pool ];
  boot.zfs.forceImportRoot = false;
  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;
  services.zfs.zed.settings.ZED_NOTIFY_VERBOSE = true;

  # --- Nix: one store for the host and all containers ---
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
  };
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 7d";
  };

  # sops-nix on the host decrypts secrets/pve2.enc.yaml with the host ssh
  # key. Copy /etc/ssh/ssh_host_ed25519_key* from pve2 before the first boot
  # so keys.hosts.pve2 in inventory/keys.nix stays valid.
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    iotop
    tmux
    lsof
    tcpdump
    dnsutils
    pciutils
    usbutils
    smartmontools
  ];

  services.smartd.enable = true;

  system.stateVersion = "26.05";
}
