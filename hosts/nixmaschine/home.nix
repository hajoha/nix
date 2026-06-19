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


  home.stateVersion = "23.11";
  programs.home-manager = {
    enable = true;
  };
}
