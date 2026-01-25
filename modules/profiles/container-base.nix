{ lib, ... }:
{
  boot.isContainer = true;
  networking.useDHCP = false;
  sops.defaultSopsFile = ./secrets.enc.yaml;
  # Global container tweaks
  services.getty.helpLine = lib.mkForce "";
  security.sudo.enable = false; # Containers usually don't need sudo if managed by host
}
