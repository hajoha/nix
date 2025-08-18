{ config, pkgs, ... }:
{
  services.opencloud.enable = true;

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
