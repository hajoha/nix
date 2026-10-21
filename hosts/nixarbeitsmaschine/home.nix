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

  imports = [
    # inputs.nvf.homeModules.default
    # ../../modules/editor/nvf.nix
    ../../modules/editor/zed.nix
    ../../modules/programs/common.nix
    ../../modules/profiles/security.nix
    ../../modules/profiles/dev.nix
    ../../modules/programs/cli.nix
    ../../modules/programs/media.nix
    # ../../modules/com/thunderbird.nix
    # ../../modules/programs/networking.nix
    ../../modules/programs/3d.nix
    ../../modules/programs/terminal.nix
    ../../modules/programs/android.nix
  ];

  home.stateVersion = "23.11";
  home.packages = [
    (pkgs.callPackage ../../pkgs/scinterface/default.nix { })
  ];
  programs.home-manager = {
    enable = true;
  };
}
