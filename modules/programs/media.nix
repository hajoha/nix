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
    (config.lib.nixGL.wrap (
      pkgs.chromium.override {
        commandLineArgs = [
          "--enable-features=UseOzonePlatform,WebRTCPipeWireCapturer,WebRTCPipeWireCamera,WebRTCPipeWireScreen"
          "--ozone-platform=wayland"
          "--enable-wayland-ime"
          "--use-gl=angle"
          "--enable-webrtc-pipewire-capturer"
          "--disable-features=WebRtcAllowInputVolumeAdjustment"
        ];
      }
    ))
  ];

  programs.obs-studio = {
    enable = true;
    plugins = with pkgs.obs-studio-plugins; [
      wlrobs # wlroots screen capture, works great on niri
    ];
  };
}
