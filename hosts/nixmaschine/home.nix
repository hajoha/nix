{
  lib,
  config,
  pkgs,
  inputs,
  nixgl,
  ...
}:
{
  imports = [
    ../../modules/home/profiles/base.nix
    ../../modules/home/profiles/desktop.nix
  ];

  gtk = {
    enable = true;
    font = {
      name = "DejaVu Sans";
      size = 10;
    };
  };

  home.stateVersion = "23.11";
  programs.home-manager = {
    enable = true;
  };

  programs.niri.settings.environment = {
    ELECTRON_OZONE_PLATFORM_HINT = "wayland";
  };
  gtk.gtk4.theme = config.gtk.theme;
  programs.yazi.shellWrapperName = "yy";
  programs.firefox.configPath = ".mozilla/firefox";
  programs.niri.settings.input.warp-mouse-to-focus.enable = true;
  home.packages = with pkgs; [
    signal-desktop
    networkmanagerapplet
  ];

}
