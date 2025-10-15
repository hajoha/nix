{
  inputs,
  config,
  pkgs,
  ...
}:

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

  imports = [
    ./hardware-configuration.nix
    ./../../modules/virt/vm.nix
    ./../../services/ollama.nix
  ];

  users.defaultUserShell = pkgs.zsh;
  environment.shells = with pkgs; [ zsh ];

  users.users.hajoha = {
    isNormalUser = true;
    description = "hajoha";
    extraGroups = [
      "networkmanager"
      "wheel"
      "kvm"
      "adbusers"
      "libvirtd"
    ];
    shell = pkgs.zsh;
    packages = with pkgs; [
      home-manager
      fwupd-efi
      nixd
    ];
  };

  services.fwupd.enable = true;
  services.flatpak.enable = true;
  services.xserver.desktopManager.xterm.enable = false;
  programs.virt-manager.enable = true;
  programs.zsh.enable = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelParams = [ "acpi.ec_no_wakeup=1̈́" ];

  system.activationScripts = {
    script.text = ''
      install -d -m 755 /home/hajoha/open-webui/data -o root -g root
    '';
  };

  networking.hostName = "nixmaschine";

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
