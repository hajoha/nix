{ config, pkgs, ... }:
{
  services.adguardhome = {
    enable = true;
    mutableSettings = false;
    settings = {
      schema_version = 29;
      http = {
        address = "10.60.1.16:3000";
      };
      users = [
        {
          name = "mng";
          password = "$2y$10$Ru/pd3y5UhFifHbwgX.gXOVL9s65EHi9JaoHbYapR3ftL1mFJSd3";
        }
      ];
      dns = {
        bind_hosts = [ "0.0.0.0" ];
        port = 53;
        upstream_dns = [ "9.9.9.9" ];
        bootstrap_dns = [ "9.9.9.9" ];
      };
      filters =
        map
          (url: {
            enabled = true;
            url = url;
          })
          [
            "https://adguardteam.github.io/HostlistsRegistry/assets/filter_9.txt" # The Big List of Hacked Malware Web Sites
            "https://adguardteam.github.io/HostlistsRegistry/assets/filter_11.txt" # malicious url blocklist
          ];
      filtering = {
        rewrites = [
          {
            domain = "*.johann-hackler.com";
            answer = "10.60.1.17";
          }
          {
            domain = "johann-hackler.com";
            answer = "10.60.1.17";
          }
        ];
        protection_enabled = true;
        filtering_enabled = true;
        parental_enabled = false; # Parental control-based DNS requests filtering.
        safe_search = {
          enabled = false; # Enforcing "Safe search" option for search engines, when possible.
        };
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
