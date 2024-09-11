{inputs, config, pkgs, ... }:

{
  nixpkgs.config.packageOverrides = pkgs: {
    nur = import (builtins.fetchTarball "https://github.com/nix-community/NUR/archive/master.tar.gz") {
      inherit pkgs;
    };
  };
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./vm.nix
#      <home-manager/nixos>
    ];


  users.defaultUserShell = pkgs.zsh;
  environment.shells = with pkgs; [ zsh ];

  users.users.hajoha = {
    isNormalUser = true;
    description = "hajoha";
    extraGroups = [ "networkmanager" "wheel"];
    shell = pkgs.zsh;
    packages = with pkgs; [
      home-manager
      fwupd-efi
    ];
  };

  services.fwupd.enable = true;
  services.flatpak.enable = true;
  services.xserver.desktopManager.xterm.enable = false;
  programs.virt-manager.enable = true;
  programs.zsh.enable = true;

	
  nix.settings.experimental-features = ["nix-command" "flakes"];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixmaschine"; # Define your hostname.


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

  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  services.xserver.xkb = {
    layout = "us";
    variant = "intl";
  };

  console.keyMap = "us-acentos";
  services.printing.enable = true;
  hardware.pulseaudio.enable = false;
  hardware.logitech.wireless.enable = true;
 
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };


  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = pkg: true;
  environment.systemPackages = with pkgs; [
    vim
  ];

  system.stateVersion = "24.05"; # Did you read the comment?
}
