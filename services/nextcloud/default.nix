{ pkgs, ... }:
{
  services.nextcloud = {
    enable = true;
    database.createLocally = true;
    config = {
      dbtype = "pgsql";
      adminpassFile = import "./../../passw/nextcloud.txt";
    };
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
