# A full personal desktop (niri + noctalia) on top of ./base.nix.
{ inputs, ... }:
{
  imports = [
    inputs.noctalia.homeModules.default
    inputs.nvf.homeManagerModules.default
    ../browser/firefox.nix
    ../mail/thunderbird.nix
    ../editor/nvf.nix
    # ../desktop/sway.nix
    ../desktop/noctalia.nix
    ../desktop/theme.nix
    ../programs/networking.nix
    ../programs/android.nix
  ];
}
