{ pkgs, config, ... }:
{
  home.packages = with pkgs; [
    gimp
    inkscape
    vlc
    ffmpeg
    papers
    poppler-utils
    steam
    # signal-desktop

  ];

  programs.obs-studio = {
    enable = true;
    plugins = with pkgs.obs-studio-plugins; [
      wlrobs # wlroots screen capture, works great on niri
    ];
  };
}
