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

  system.stateVersion = "25.11";
}
