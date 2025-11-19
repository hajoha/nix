{ config, pkgs, ... }:

{
  services.nginx = {
    enable = true;
    logError = "stderr debug";
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    #    recommendedProxySettings = true;
    recommendedTlsSettings = true;
        sslCiphers = "AES256+EECDH:AES256+EDH:!aNULL";

    appendHttpConfig = ''
        map $http_upgrade $connection_upgrade {
                default upgrade;
                /'/'      close;
        }
    '';
    virtualHosts = {
      "johann-hackler.com" = {
        useACMEHost = "johann-hackler.com";
        forceSSL = true;
        acmeRoot = null;
        locations."/.well-known/webfinger" = {
          extraConfig = ''
            add_header Content-Type application/jrd+json;
            return 200 '{"subject":"acct:info@johann-hackler.com","links":[{"rel":"http://openid.net/specs/connect/1.0/issuer","href":"https://zitadel.johann-hackler.com"}]}';
          '';
        };

      };
      "opencloud.johann-hackler.com" = {
        useACMEHost = "johann-hackler.com";
        forceSSL = true;
        acmeRoot = null;
        locations."/" = {
          proxyPass = "https://10.60.1.14:9200";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';

        };
        extraConfig = ''
          if ($remote_addr !~ ^10\.60\.) {
            return 444;
          }

        '';
      };
      "adguard.johann-hackler.com" = {
        useACMEHost = "johann-hackler.com";
        forceSSL = true;
        acmeRoot = null;
        locations."/" = {
          proxyPass = "http://10.60.1.16:3000";
        };
        extraConfig = ''
          if ($remote_addr !~ ^10\.60\.) {
            return 444;
          }
        '';
      };
      "openwrt.johann-hackler.com" = {
        useACMEHost = "johann-hackler.com";
        forceSSL = true;
        acmeRoot = null;
        locations."/" = {
          proxyPass = "http://10.60.1.1"; # Proxmox HTTPS backend
        };

        # Only allow LAN access
        extraConfig = ''
          if ($remote_addr !~ ^10\.60\.) {
            return 444;
          }
        '';
      };
      # Internal-only Proxmox
      "pve1.johann-hackler.com" = {
        useACMEHost = "johann-hackler.com";
        forceSSL = true;
        acmeRoot = null;
        locations."/" = {
          proxyPass = "https://10.60.0.3:8006/"; # Proxmox HTTPS backend
        };

        # Only allow LAN access
        extraConfig = ''
          if ($remote_addr !~ ^10\.60\.) {
            return 444;
          }
        '';
      };
      "grafana.johann-hackler.com" = {
        useACMEHost = "johann-hackler.com";
        forceSSL = true;
        acmeRoot = null;
        locations."/" = {
          proxyPass = "http://10.60.1.25:3000";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };
      "influxv2.johann-hackler.com" = {
        useACMEHost = "johann-hackler.com";
        forceSSL = true;
        acmeRoot = null;
        locations."/" = {
          proxyPass = "http://10.60.1.26:8086";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };
      "zitadel.johann-hackler.com" = {
        useACMEHost = "johann-hackler.com";
        forceSSL = true;
        acmeRoot = null;
        http2 = true;
        locations."/" = {
          proxyPass = "http://10.60.1.21:8081";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-Port 443;
          '';
        };
        # Only allow LAN access
        #        extraConfig = ''
        #          if ($remote_addr !~ ^10\.60\.) {
        #            return 444;
        #          }
        #        '';
      };
      "hedgedoc.johann-hackler.com" = {
#        useACMEHost = "johann-hackler.com";
        enableACME = true;
        forceSSL = true;
        acmeRoot = null;
        http2 = true;
        locations."/socket.io/" = {
          proxyPass = "http://10.60.1.23:8001";
          proxyWebsockets = true;
          extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
                proxy_set_header X-Forwarded-Host $host;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection $connection_upgrade;
            '';
        };
        locations."/" = {
          proxyPass = "http://10.60.1.23:8001";
          extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
                proxy_set_header X-Forwarded-Host $host;
          '';

        };
      };
      "headscale.johann-hackler.com" = {
        useACMEHost = "johann-hackler.com";
        forceSSL = true;
        acmeRoot = null;

        locations."/" = {
          proxyPass = "http://10.60.1.22:8080";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Host $server_name;
            proxy_redirect http:// https://;
            proxy_buffering off;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;

          '';

        };

        locations."/admin/" = {
          proxyPass = "http://10.60.1.22:3000/admin/";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Host $host;
            proxy_redirect http:// https://;
            proxy_buffering off;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };

        locations."/admin" = {
          extraConfig = ''
            return 301 /admin/;
          '';
        };

      };

    };
  };

  security.acme = {
    acceptTerms = true;

    certs."johann-hackler.com" = {
      extraDomainNames = [ "*.johann-hackler.com" ];
      dnsProvider = "inwx";
      email = "joh.hackler@gmail.com";
      credentialFiles = {
        "INWX_USERNAME_FILE" = config.sops.secrets."INWX_USERNAME".path;
        "INWX_PASSWORD_FILE" = config.sops.secrets."INWX_PASSWORD".path;
      };
      dnsPropagationCheck = false;
    };
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
