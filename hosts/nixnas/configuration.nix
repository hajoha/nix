{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./../../services/ssh/default.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nix-nas";
  users.users = import ./../../user/mng.nix { inherit pkgs; };

  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Berlin";
  nix.gc = {
    automatic = true; # Enable automatic garbage collection
    dates = "weekly"; # Run weekly (or "daily", "03:15" etc.)
    options = "--delete-older-than 2d"; # Delete generations older than 30 days
  };

  i18n.defaultLocale = "en_US.UTF-8";

  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    tcpdump
    ethtool
    iperf3
  ];

security.sudo.extraRules = [
  {
    users = [ "mng" ];
    commands = [
      {
        command = "ALL";
        options = [ "NOPASSWD" ];
      }
    ];
  }
];

  networking = {
    interfaces.eno1 = {
      ipv4.addresses = [
        {
          address = "10.60.0.20";
          prefixLength = 24;
        }
      ];
    };
    interfaces.enp3s0f1np1 = {
      ipv4.addresses = [
        {
          address = "10.60.1.120";
          prefixLength = 24;
        }
      ];
    };
    vlans = {
        oob = { id=4000; interface="enp3s0f1np1"; };
    };
    interfaces.oob.ipv4.addresses = [{
        address = "192.168.0.120";
        prefixLength = 24;
    }];
  };

  system.stateVersion = "25.11";

}
