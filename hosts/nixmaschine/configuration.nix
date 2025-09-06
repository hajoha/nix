{ inputs, config, pkgs, ... }:

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
      ./hardware-configuration.nix
      ./../../modules/virt/vm.nix
      ./../../services/ollama.nix
    ];


  users.defaultUserShell = pkgs.zsh;
  environment.shells = with pkgs; [ zsh ];

  users.users.hajoha = {
    isNormalUser = true;
    description = "hajoha";
    extraGroups = [ "networkmanager" "wheel" "kvm" "adbusers" "libvirtd" ];
    shell = pkgs.zsh;
    packages = with pkgs; [
      home-manager
      fwupd-efi
      nixd
    ];
  };

  services.fwupd.enable = true;
  services.flatpak.enable = true;
  xdg = {
    autostart.enable = true;
    portal = {
      enable = true;
      xdgOpenUsePortal = false;
      wlr.enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal
        xdg-desktop-portal-gtk
        xdg-desktop-portal-wlr
      ];
      config = {
        sway = {
          default = [ "gtk" ];
          "org.freedesktop.impl.portal.OpenURI" = "gtk";
          "org.freedesktop.impl.portal.Screencast" = "wlr";
          "org.freedesktop.impl.portal.Screenshot" = "wlr";
          "org.freedesktop.impl.portal.GlobalShortcuts" = "gtk";
        };
      };
    };
  };


  programs.virt-manager.enable = true;
  programs.zsh.enable = true;
  programs._1password.enable = true;
  programs._1password-gui.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

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
  fonts.fontconfig.enable = true;
  fonts.packages = with pkgs; [
    dejavu_fonts # fallback sans-serif
    liberation_ttf # fallback sans-serif / monospace
    noto-fonts # wide Unicode coverage
    noto-fonts-cjk-sans # CJK characters
    noto-fonts-emoji # emoji
    twemoji-color-font # optional color emoji
    nerd-fonts.symbols-only # Nerd icons
    nerd-fonts.fira-code # patched Fira Code
    fira-code # monospaced font
  ];
  security.pam.services.swaylock = { };

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


  services.xserver.xkb = {
    layout = "us";
    variant = "intl";
  };

  console.keyMap = "us-acentos";
  services.printing.enable = true;

  services.pulseaudio.enable = false;
  hardware.logitech.wireless.enable = true;
  security.rtkit.enable = true;
  security.polkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = ''
          tuigreet --time --cmd sway
        '';
        user = "hajoha";
      };
    };
  };

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = pkg: true;
  environment.systemPackages = with pkgs; [
    vim
    glib
    xdg-utils
  ];

  system.stateVersion = "24.05"; # Did you read the comment?
}
