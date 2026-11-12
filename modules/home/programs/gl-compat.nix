{
  pkgs,
  nixgl,
  config,
  lib,
  ...
}:
{
  targets.genericLinux.enable = true;
  targets.genericLinux.nixGL = {
    packages = import nixgl { inherit pkgs; };
    defaultWrapper = "mesa";
    installScripts = [ "mesa" ];
  };

  # Move your specific LD_LIBRARY_PATH hacks here
  home.sessionVariables = {
    NIX_LD_LIBRARY_PATH = "/usr/lib/x86_64-linux-gnu:${pkgs.stdenv.cc.cc.lib}/lib";
    NIX_LD = "${pkgs.stdenv.cc.cc.lib}/lib/ld-linux-x86-64.so.2";
    LD_LIBRARY_PATH = "${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.pcsclite}/lib:${config.home.profileDirectory}/lib";
  };
}
