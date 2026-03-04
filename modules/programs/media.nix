{ pkgs, ... }:
{
  home.packages = with pkgs; [
    gimp
    inkscape
    vlc
    ffmpeg
    papers
    poppler-utils
    signal-desktop
    chromium
  ];
}
