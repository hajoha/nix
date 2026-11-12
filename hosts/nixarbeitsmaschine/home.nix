{
  lib,
  config,
  pkgs,
  inputs,
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

  # Work laptop: base profile only (no desktop, nvf, mail, android).
  imports = [ ../../modules/home/profiles/base.nix ];

  home.stateVersion = "23.11";
  home.packages = [
    (pkgs.callPackage ../../pkgs/scinterface/default.nix { })
  ];
  programs.home-manager = {
    enable = true;
  };
}
