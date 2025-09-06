{ config, pkgs, ... }:
{
  services.opencloud = {
    enable = true;
    url = "https://10.60.0.14:9200";
    address = "10.60.0.14";
    settings = {
      OC_DOMAIN = "cloud.pwn";
    };
  };

  networking.firewall.allowedTCPPorts = [ 9200 ];
}
