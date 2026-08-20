{
  lib,
  config,
  system,
  pkgs,
  inputs,
  nixgl,
  ...
}:
{
  nixpkgs = {
    overlays = [
      inputs.nur.overlays.default
    ];
    config = {
      allowUnfree = true;
    };
  };

  xdg.desktopEntries = {
    signal-desktop = {
      name = "Signal";
      exec = "nixGLMesa ${pkgs.signal-desktop}/bin/signal-desktop --no-sandbox --enable-features=UseOzonePlatform --ozone-platform=wayland %u";
      icon = "signal-desktop";
      terminal = false;
      categories = [
        "Network"
        "InstantMessaging"
      ];
    };
  };

  programs.firefox = {
    package = config.lib.nixGL.wrap pkgs.firefox;
  };

  programs.ghostty = {
    package = config.lib.nixGL.wrap pkgs.ghostty;
  };
  programs.niri.enable = true;
  systemd.user.services.xdg-desktop-portal-gtk = {
    Service.ExecStart = [
      ""
      "${pkgs.xdg-desktop-portal-gtk}/libexec/xdg-desktop-portal-gtk"
    ];
  };

  systemd.user.services.xdg-desktop-portal = {
    Service.ExecStart = [
      "" # clear the ubuntu default
      "${pkgs.xdg-desktop-portal}/libexec/xdg-desktop-portal"
    ];
  };

  systemd.user.services.xdg-desktop-portal-wlr = {
    Service.ExecStart = [
      ""
      "${pkgs.xdg-desktop-portal-wlr}/libexec/xdg-desktop-portal-wlr"
    ];
  };
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-wlr
    ];
    config = {
      common.default = [ "gtk" ];
      niri = {
        default = [ "gtk" ];
        "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
        "org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];
      };
    };
  };

  programs.hyprlock = {
    package = pkgs.runCommand "empty" { } "mkdir -p $out";
  };

  services.hypridle = {
    package = pkgs.runCommand "empty-hypridle" { } "mkdir -p $out";
  };
  imports = [
    inputs.noctalia.homeModules.default
    inputs.nvf.homeManagerModules.default
    inputs.niri.homeModules.niri
    ../../modules/browser/firefox.nix
    ../../modules/com/thunderbird.nix
    ../../modules/editor/nvf.nix
    ../../modules/editor/zed.nix
    #../../modules/desktop/sway.nix
    ../../modules/desktop/noctalia.nix

    ../../modules/programs/common.nix
    ../../modules/profiles/security.nix
    ../../modules/profiles/dev.nix
    ../../modules/desktop/theme.nix
    ../../modules/programs/cli.nix
    ../../modules/programs/media.nix
    ../../modules/programs/networking.nix
    ../../modules/programs/3d.nix
    ../../modules/programs/terminal.nix
    ../../modules/programs/android.nix
  ];
  targets.genericLinux.enable = true;

  systemd.user.startServices = "sd-switch";
  services.gnome-keyring = {
    enable = lib.mkForce false;
    components = [
      # "secrets"
      # "ssh"
    ];
  };

  targets.genericLinux.nixGL.packages = import nixgl { inherit pkgs; };
  targets.genericLinux.nixGL.defaultWrapper = "mesa";
  targets.genericLinux.nixGL.installScripts = [ "mesa" ];
  home.packages = with pkgs; [
    (pkgs.callPackage ../../pkgs/scinterface/default.nix { })
    pkgs.xwayland-satellite
    libxcursor
    libxext
    libx11
    libxrender
  ];

  systemd.user.services.xwayland-satellite = {
    Unit = {
      Description = "Xwayland outside your Wayland";
      BindsTo = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      Requisite = [ "graphical-session.target" ];
    };
    Service = {
      Type = "notify";
      NotifyAccess = "all";
      ExecStart = "${pkgs.xwayland-satellite}/bin/xwayland-satellite";
      StandardOutput = "journal";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
  home.sessionVariables = {
    QT_STYLE_OVERRIDE = "kvantum";
    XDG_SESSION_DESKTOP = "niri";
    XDG_CURRENT_DESKTOP = "niri";
    OPENSC_CONF = "$HOME/.config/opensc/opensc.conf";
    NIX_LD_LIBRARY_PATH = "/usr/lib/x86_64-linux-gnu:${pkgs.stdenv.cc.cc.lib}/lib";

    NIX_LD = "${pkgs.stdenv.cc.cc.lib}/lib/ld-linux-x86-64.so.2";
    LD_LIBRARY_PATH = "${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.pcsclite}/lib:${config.home.profileDirectory}/lib";
    XDG_SESSION_TYPE = "wayland";
    GDK_BACKEND = "wayland,x11";
    TERMINFO_DIRS = "${pkgs.ghostty.terminfo}/share/terminfo:${config.home.profileDirectory}/share/terminfo:/usr/share/terminfo";
    XDG_DATA_DIRS = lib.mkForce "$HOME/.nix-profile/share:$HOME/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:$XDG_DATA_DIRS:/usr/local/share:/usr/share";
    # DISPLAY = ":0";
    #XDG_DATA_DIRS = lib.mkForce "${config.home.profileDirectory}/share:$HOME/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share";

    # Forces GTK apps to use the portal for file pickers
    #GTK_USE_PORTAL = "1";
  };

  home.stateVersion = "23.11";
  # Let home Manager install and manage itself.
  programs.home-manager = {
    enable = true;
  };
}
