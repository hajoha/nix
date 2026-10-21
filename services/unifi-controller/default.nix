{
  config,
  pkgs,
  lib,
  nodes,
  ...
}:

{

  nixpkgs.config.allowUnfree = true;
  services.unifi.enable = true;
  services.unifi.openFirewall = true;
  services.unifi.mongodbPackage = pkgs.mongodb-ce;
  services.unifi.unifiPackage = pkgs.unifi.overrideAttrs (old: {
    buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.stdenv.cc.cc.lib ];
  });
  system.stateVersion = "25.11";
}
