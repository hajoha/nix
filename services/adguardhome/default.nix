{
  config,
  pkgs,
  lib,
  nodes,
  baseDomain,
  ...
}:
{
  services.adguardhome = {
    enable = true;
    mutableSettings = false;
    settings = {
      schema_version = 29;
      http = {
        # Binds to 0.0.0.0 so it is accessible on 10.60.1.53:3000
        address = "0.0.0.0:3000";
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
        upstream_dns = [
          "9.9.9.9"
          "1.1.1.1"
        ];
        bootstrap_dns = [ "9.9.9.9" ];
      };
      filters =
        map
          (url: {
            enabled = true;
            inherit url;
          })
          [
            "https://adguardteam.github.io/HostlistsRegistry/assets/filter_9.txt"
            "https://adguardteam.github.io/HostlistsRegistry/assets/filter_11.txt"
          ];
      filtering = {
        rewrites = [
          {
            domain = "*.johann-hackler.com";
            # Now points to the Nginx LXC's IP from network.nix
            answer = "${nodes.nix-nginx.ip}";
          }
          {
            domain = "johann-hackler.com";
            answer = "${nodes.nix-nginx.ip}";
          }
        ];
        protection_enabled = true;
        filtering_enabled = true;
      };
    };
  };

  # Disable systemd-resolved to prevent port 53 conflicts
  services.resolved.enable = false;

  # Note: networking.firewall is now handled by mkLXC + network.nix
  # so it is omitted here to keep the service file clean.

  system.stateVersion = "25.11";
}
