{ pkgs, ... }:
{
  home.packages = with pkgs; [
    gimp
    inkscape
    vlc
    ffmpeg
    papers
    poppler-utils
    # signal-desktop
    (pkgs.chromium.override {
      commandLineArgs = [
        "--enable-features=UseOzonePlatform,WebRTCPipeWireCapturer,WebRTCPipeWireCamera"
        "--ozone-platform=wayland"
        "--enable-wayland-ime"
        "--use-gl=angle"
      ];
    })

  ];
}
