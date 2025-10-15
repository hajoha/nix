{ config, pkgs, ... }:

{
  services.nginx = {
    enable = true;

    virtualHosts = {
      # Public AdGuard
      "johann-hackler.com" = {
        enableACME = true;
        forceSSL = true;
        acmeRoot = null;
      };
      "adguard.johann-hackler.com" = {
        enableACME = true;
        forceSSL = true;
        acmeRoot = null;
        locations."/" = {
          proxyPass = "http://10.60.0.16:3000";
        };
        extraConfig = ''
          allow 10.60.0.0/16;
          deny all;
        '';
      };

      # Internal-only Proxmox
      "pve1.johann-hackler.com" = {
        enableACME = true;
        forceSSL = true;
        acmeRoot = null;
        locations."/" = {
          proxyPass = "https://10.60.0.3:8006/"; # Proxmox HTTPS backend
        };

        # Only allow LAN access
        extraConfig = ''
          allow 10.60.0.0/16;
          deny all;
        '';
      };
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults = {
      dnsProvider = "inwx";
      email = "joh.hackler@gmail.com";
      credentialFiles = {
        "INWX_USERNAME_FILE" = "/run/secrets/INWX_USERNAME";
        "INWX_PASSWORD_FILE" = "/run/secrets/INWX_PASSWORD";
      };
      # We don't need to wait for propagation since this is a local DNS server
      dnsPropagationCheck = false;
    };

  };

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
