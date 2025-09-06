{ lib, config, system, pkgs, inputs, ... }:
{

  nixpkgs = {
    overlays = [
      inputs.nur.overlay
    ];

  };



  home.packages = with pkgs; [
    # 3D-stuff
    tmux
    zip
    iperf3

  ];


  programs.git = {
    enable = true;
    userName = "hajoha";
    userEmail = "hajoha1@proton.me";
  };


  home.stateVersion = "24.11";

  # Let home Manager install and manage itself.
  programs.home-manager.enable = true;
}
