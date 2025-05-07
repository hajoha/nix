{inputs, config, pkgs, ... }:

{
  nixpkgs.config = {
    packageOverrides = pkgs: {
        nur = import (builtins.fetchTarball "https://github.com/nix-community/NUR/archive/master.tar.gz") {
          inherit pkgs;
        };
    };
                  permittedInsecurePackages = [
                "dotnet-sdk_7"
              ];
  };

  imports =
    [
        ./../../services/ssh.nix
    ];


  users.users = import ./../../user/mng.nix { inherit pkgs; };

  services.fwupd.enable = true;

	
  nix.settings.experimental-features = ["nix-command" "flakes"];

  boot.loader.systemd-boot.enable = true;





  networking.hostName = "nixlxc";


  networking.networkmanager.enable = true;
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_DE.UTF-8";
    LC_IDENTIFICATION = "de_DE.UTF-8";
    LC_MEASUREMENT = "de_DE.UTF-8";
    LC_MONETARY = "de_DE.UTF-8";
    LC_NAME = "de_DE.UTF-8";
    LC_NUMERIC = "de_DE.UTF-8";
    LC_PAPER = "de_DE.UTF-8";
    LC_TELEPHONE = "de_DE.UTF-8";
    LC_TIME = "de_DE.UTF-8";
  };

  services.xserver.enable = true;


  services.xserver.xkb = {
    layout = "us";
    variant = "intl";
  };

  console.keyMap = "us-acentos";
  services.printing.enable = true;
  security.rtkit.enable = true;


  nixpkgs.config.allowUnfreePredicate = pkg: true;
  environment.systemPackages = with pkgs; [
    vim
  ];

  system.stateVersion = "24.11"; # Did you read the comment?
}
