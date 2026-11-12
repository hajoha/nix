# Everything every machine gets: shell, editor, dev tooling, CLI apps.
{
  imports = [
    ../editor/zed.nix
    ../programs/common.nix
    ../programs/security.nix
    ../programs/dev.nix
    ../programs/cli.nix
    ../programs/media.nix
    ../programs/3d.nix
    ../programs/terminal.nix
  ];
}
