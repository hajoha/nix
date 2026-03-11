{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./disko-config.nix
    ../../user/root.nix
  ];

  boot.loader.grub.enable = true;

  sops.defaultSopsFile = ./serets.enc.yaml;
  sops.secrets."wg.privat" = {
    # Optional: set owner if wireguard needs specific access,
    # though usually root-read is fine for networking.wireguard.
    owner = "root";
  };
  users.users.mng = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialHashedPassword = "$y$j9T$HcqSvbzpNSFp3ITAbUNpi.$5yehhQXXNrNvHt.XxVBkIxJ1bAxy4V4NkkjYeXVPdQ4"; # Password.123
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIocRHpz5SimboTEV6r/YGafvLqNO5qH//VdzcInV/CB hajoha"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIINQi5Dlk3UEpkbi0lJOe0EsEnbxW5Mdhe2kf/yX/uy+ hajoha"
    ];
  };
  networking.firewall.allowedUDPPorts = [ 51820 ]; # Open the WireGuard port
  networking.wireguard.interfaces = {
    wg0 = {
      ips = [ "10.100.0.1/24" ];
      listenPort = 51820;

      # Path to your private key file on the server
      privateKeyFile = config.sops.secrets."wg.privat".path;

      peers = [
        {
          # The single peer you want to connect
          publicKey = "";
          # Only allow traffic to/from this specific internal tunnel IP
          allowedIPs = [ "10.100.0.2/32" ];
        }
      ];
    };
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };

  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings = {
      PasswordAuthentication = false;
      AllowUsers = [ "mng" ]; # Allows all users by default. Can be [ "user1" "user2" ]
      UseDns = true;
      X11Forwarding = false;
      PermitRootLogin = "no"; # "yes", "without-password", "prohibit-password", "forced-commands-only", "no"
    };
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  system.stateVersion = "25.11";
}
