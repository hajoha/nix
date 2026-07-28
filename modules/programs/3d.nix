{ pkgs, inputs, ... }:
let
  pkgs-freecad = import inputs.nixpkgs-freecad {
    inherit (pkgs) system;
  };
in
{
  home.packages =
    with pkgs;
    [
      blender
      # bambu-studio
    ]
    ++ [ pkgs-freecad.freecad ];
}
