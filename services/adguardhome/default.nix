{ config, pkgs, ... }:

{
  services.adguardhome = {
    enable = true;
    mutableSettings = false;
    settings = {
      schema_version = 29;
      http = {
        # Changed from 10.60.1.16 to 0.0.0.0 so it binds to the
        # container's internal eth0 (172.16.0.10)
        address = "0.0.0.0:3000";
      };
      users = [
        {
          name = "mng";
          # Tip: In the future, move this hash to a sops-nix secret
          password = "$2y$10$Ru/pd3y5UhFifHbwgX.gXOVL9s65EHi9JaoHbYapR3ftL1mFJSd3";
        }
      ];
      dns = {
        bind_hosts = [ "0.0.0.0" ];
        port = 53;
        upstream_dns = [ "9.9.9.9" "1.1.1.1" ];
        bootstrap_dns = [ "9.9.9.9" ];
      };
      filters = map (url: { enabled = true; inherit url; }) [
        "https://adguardteam.github.io/HostlistsRegistry/assets/filter_9.txt"
        "https://adguardteam.github.io/HostlistsRegistry/assets/filter_11.txt"
      ];
      filtering = {
        rewrites = [
          {
            domain = "*.johann-hackler.com";
            # Changed to point to the Nginx Container's internal IP
            answer = "172.16.0.2";
          }
          {
            domain = "johann-hackler.com";
            answer = "172.16.0.2";
          }
        ];
        protection_enabled = true;
        filtering_enabled = true;
      };
    };
  };

  # Since this is a container, we disable resolved to avoid
  # port 53 conflicts with AdGuard inside the container.
  services.resolved.enable = false;

  # Networking for the container
  networking = {
    firewall = {
      enable = true;
      allowedTCPPorts = [ 53 3000 ];
      allowedUDPPorts = [ 53 ];
    };
  };
  system.stateVersion = "25.11";
}