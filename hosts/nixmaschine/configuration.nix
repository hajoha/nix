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
    inputs.niri.nixosModules.niri
    #    ./../../modules/virt/vm.nix
  ];

  users.defaultUserShell = pkgs.zsh;
  environment.shells = with pkgs; [ zsh ];
  nixpkgs.overlays = [ inputs.nur.overlays.default ];
  users.users.hajoha = {
    isNormalUser = true;
    description = "hajoha";
    extraGroups = [
      "networkmanager"
      "wheel"
      "kvm"
      "adbusers"
      "librepods"
      "libvirtd"
    ];
  };

  services.flatpak.enable = true;
  hardware.bluetooth.enable = true;
  services.power-profiles-daemon.enable = true;
  programs.dconf.enable = true;
  services.upower.enable = true;
  environment.pathsToLink = [
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];
  programs.niri.enable = true;
  services.fwupd.enable = true;
  programs.git.enable = true;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelParams = [ "acpi.ec_no_wakeup=1" ];
  networking.networkmanager.ensureProfiles.profiles = {
    eduroam = {
      connection = {
        id = "eduroam";
        type = "wifi";
        autoconnect = true;
      };
      wifi = {
        ssid = "eduroam";
        mode = "infrastructure";
      };
      wifi-security = {
        key-mgmt = "wpa-eap";
      };
      "802-1x" = {
        eap = "peap";
        identity = "joh.hackler@tu-berlin.de";
        anonymous-identity = "wlan@tu-berlin.de";
        phase2-auth = "mschapv2";
        ca-cert = "/home/hajoha/.config/cat_installer/ca.pem";
        password-flags = 0; # let NM handle the password securely
      };
    };
  };
  environment.systemPackages = [
    pkgs.ghostty.terminfo

  ];

  services.printing = {
    enable = true;
    drivers = with pkgs; [ hplipWithPlugin ];
  };

  programs.librepods.enable = true;

  # Enable hardware scanning (for the scanner portion of the MFP)
  hardware.sane = {
    enable = true;
    extraBackends = [ pkgs.hplipWithPlugin ];
  };
  networking.hostName = "nixmaschine";
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  networking.networkmanager.enable = true;
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";
  fonts.fontconfig.enable = true;

  fonts.fontconfig.defaultFonts = {
    sansSerif = [
      "DejaVu Sans"
      "Noto Sans"
    ];
    serif = [
      "Noto Serif"
      "DejaVu Serif"
    ];
    monospace = [
      "Fira Code"
      "DejaVu Sans Mono"
    ];
    emoji = [ "Noto Color Emoji" ];
  };

  fonts.packages = with pkgs; [
    dejavu_fonts # fallback sans-serif
    liberation_ttf # fallback sans-serif / monospace
    noto-fonts # wide Unicode coverage
    noto-fonts-cjk-sans # CJK characters
    noto-fonts-color-emoji # emoji
    twemoji-color-font # optional color emoji
    nerd-fonts.symbols-only # Nerd icons
    nerd-fonts.fira-code # patched Fira Code
    fira-code # monospaced font
  ];

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

  programs.zsh.enable = true;
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
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd niri-session";
        user = "greeter";
      };
    };
  };

  services.dbus.implementation = "dbus";
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = pkg: true;

  system.stateVersion = "24.05"; # Did you read the comment?
  services.xserver.xkb = {
    layout = "us";
    variant = "altgr-intl";
  };
  console.useXkbConfig = true;

  services.tailscale = {
    enable = true;
    extraUpFlags = [ "--operator=hajoha" ];
  };

}
