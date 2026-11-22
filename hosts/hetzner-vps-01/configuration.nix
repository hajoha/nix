{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Managed with ./wg-peer.sh, keys in sops (wireguard.enc.yaml by default)
  wgPeers = lib.importJSON ./wireguard-peers.json;
in
{
  imports = [
    ./hardware-configuration.nix
    ./disko-config.nix
    ../../user/root.nix
  ];

  boot.loader.grub.enable = true;

  sops.defaultSopsFile = ./secrets.enc.yaml;
  sops.secrets = {
    "wg.privat" = {
      # Optional: set owner if wireguard needs specific access,
      # though usually root-read is fine for networking.wireguard.
      owner = "root";
    };
  }
  // lib.listToAttrs (
    map (
      p: lib.nameValuePair "${p.name}/psk" { sopsFile = ./. + "/${p.sopsFile or "wireguard.enc.yaml"}"; }
    ) wgPeers
  );
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
      ips = [ "10.60.71.1/24" ];
      listenPort = 51820;

      # Path to your private key file on the server
      privateKeyFile = config.sops.secrets."wg.privat".path;

      # Only allow traffic to/from each peer's own tunnel IP
      peers = map (p: {
        inherit (p) name publicKey;
        presharedKeyFile = config.sops.secrets."${p.name}/psk".path;
        allowedIPs = [ "${p.ip}/32" ];
      }) wgPeers;
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

  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    bantime-increment = {
      enable = true;
      maxtime = "168h";
    };
    ignoreIP = [ "10.60.71.0/24" ];
    jails.sshd.settings = {
      findtime = "1d"; # the bots retry every 12-17 min, the default window is 10 min
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
