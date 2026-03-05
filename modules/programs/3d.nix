{ pkgs, ... }:
{
  home.packages = with pkgs; [
    blender
    freecad
    # bambu-studio
  ];
}
