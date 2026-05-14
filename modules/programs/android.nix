{ pkgs, config, ... }:
{
  home.packages = [
    (config.lib.nixGL.wrap pkgs.android-studio)
    pkgs.android-tools
  ];
}
