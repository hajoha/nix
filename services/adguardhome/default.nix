{ config, pkgs, ... }:
{
  services.adguardhome = {
    enable = true;
    mutableSettings = false;
    settings = {
      schema_version = 29;
      http = {
        address = "10.60.0.16:3000";
      };
      users = [
        {
          name = "mng";
          password = "$2y$10$3BaLeYP0VNxo4BENt3Woj.RqtaHgmEZQWNxg2eN8xdN71NzVMEDai";
        }
      ];
      dns = {
        bind_hosts = [ "0.0.0.0" ];
        port = 53;
        upstream_dns = [ "9.9.9.9" ];
        bootstrap_dns = [ "9.9.9.9" ];
      };
      filtering = {
        rewrites = [
          {
            domain = "*.bar0.foo";
            answer = "10.60.0.17";
          }
        ];
      };
      tls = {
        #        enabled = true;
        #force_https = true;
      };
    };
  };

  services.resolved.enable = false;

  networking.firewall.allowedTCPPorts = [
    53
    3000
  ];
  networking.firewall.allowedUDPPorts = [ 53 ];
}
