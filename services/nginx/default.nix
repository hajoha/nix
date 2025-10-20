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
          if ($remote_addr !~ ^10\.60\.) {
            return 444;
          }
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
          if ($remote_addr !~ ^10\.60\.) {
            return 444;
          }
        '';
      };
      "zitadel.johann-hackler.com" = {
        enableACME = true;
        forceSSL = true;
        acmeRoot = null;
        locations."/" = {
          proxyPass = "http://10.60.0.21:8081"; # Proxmox HTTPS backend
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Forwarded-For $remote_addr;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Port 443;
          '';
        };
        # Only allow LAN access
        extraConfig = ''
          if ($remote_addr !~ ^10\.60\.) {
            return 444;
          }
        '';
      };
      "netbird.johann-hackler.com" = {
        enableACME = true;
        forceSSL = true;
        acmeRoot = null;

        locations = {

          # Management REST (HTTP)
          "/api" = {
            proxyPass = "http://10.60.0.22:80";
            proxyWebsockets = true;
            extraConfig = '''';
          };

          # Management gRPC
          "/management.ManagementService/" = {
            extraConfig = ''
              client_body_timeout 1d;
              grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              grpc_pass grpc://10.60.0.22:80;
              grpc_read_timeout 1d;
              grpc_send_timeout 1d;
              grpc_socket_keepalive on;
            '';
          };

          # Management WS proxy (if used)
          "/ws-proxy/management" = {
            proxyPass = "http://10.60.0.22:80";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Host $host;
            '';
          };

          # Signal gRPC
          "/signalexchange.SignalExchange/" = {
            extraConfig = ''
              grpc_pass grpc://10.60.0.22:80;
              grpc_set_header Host $host;
              grpc_set_header X-Forwarded-Proto https;
            '';
          };

          # Signal WebSocket for clients (match Signal.URI above)
          "/ws-proxy/signal" = {
            proxyPass = "http://10.60.0.22:9091";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Host $host;
            '';
          };

          # Relay WS
          "/relay" = {
            proxyPass = "http://10.60.0.22:33080";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Host $host;
            '';
          };
          "/" = {
            proxyPass = "http://10.60.0.22:8011";
            proxyWebsockets = true;
            extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Forwarded-Proto $scheme;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            '';
          };

        };

        #       Remove this block if clients connect from outside your LAN
        extraConfig = ''
          if ($remote_addr !~ ^10\.60\.) { return 444; }
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
