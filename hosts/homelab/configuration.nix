# The homelab server: NixOS on bare metal.
# Every service runs as a NixOS container generated from the inventory
# (modules/nixos/homelab-host.nix); this file is the host itself.
{
  lib,
  pkgs,
  params,
  ...
}:
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ./network.nix
    ./containers.nix
    ./backup.nix
    ./container-keys.nix
    ./ci.nix
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
  # The pool is encrypted (passphrase). Import it at boot without asking, so
  # the box comes up headless; unlock over ssh:
  #   zfs load-key threetbpool && zfs mount -a
  # Containers with data on it wait until then (hosts/homelab/containers.nix).
  boot.zfs.requestEncryptionCredentials = false;
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

  # sops-nix on the host decrypts hosts/homelab/secrets.enc.yaml with the
  # host's ssh key; its age key is hosts.homelab in inventory/keys.nix
  # (`homelab-age-keys` prints it).
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # services/build signs with /etc/nix/signing-key.sec, which this host does
  # not have; a missing key would make every local build fail.
  nix.settings.secret-key-files = lib.mkForce [ ];

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
