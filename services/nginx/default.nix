{
  config,
  pkgs,
  nodes,
  baseDomain,
  ...
}:

let
  commonProxy = {
    proxyWebsockets = true;
    extraConfig = ''
      proxy_set_header Host ''$host;
      proxy_set_header X-Real-IP ''$remote_addr;
      proxy_set_header X-Forwarded-For ''$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto ''$scheme;
      proxy_set_header X-Forwarded-Host ''$host;
    '';
  };

  lanOnly = ''
    allow 10.60.0.0/16;
    allow 100.64.0.0/10;
    allow 127.0.0.1;
    deny all;
    error_page 403 =444 /;
  '';
in
{

  sops.defaultSopsFile = ./secrets.enc.yaml;

  services.fail2ban = {
    enable = true;
    # Max retry attempts before banning
    maxretry = 5;
    # Ban for 1 hour
    bantime = "1h";

    # Whitelist your local LAN so you don't lock yourself out
    ignoreIP = [
      "127.0.0.1"
      "10.60.0.0/16"
      "100.64.0.0/10" # Tailscale/Headscale range
    ];

    jails = {
      # Standard SSH protection
      sshd.settings = {
        enabled = true;
      };

      # Nginx protection - looks for 4xx and 5xx errors
      nginx-http-auth = {
        settings = {
          enabled = true;
          filter = "nginx-http-auth";
          port = "http,https";
          logpath = "/var/log/nginx/error.log";
        };
      };

      # Custom jail for your "lanOnly" 444 returns (unauthorized access)
      nginx-unauthorized = {
        settings = {
          enabled = true;
          port = "http,https";
          filter = "nginx-botsearch";
          logpath = "/var/log/nginx/access.log";
          maxretry = 3;
        };
      };
    };
  };
  # 2. Tell sops-nix which keys to decrypt
  sops.secrets."acme-inwx-env" = {
    owner = "acme";
  };
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedTlsSettings = true;

    appendHttpConfig = ''
      map ''$http_upgrade ''$connection_upgrade {
          default upgrade;
          # Escaped empty string for Nginx
          '''       close;
      }
    '';

    virtualHosts = {
      # --- Root Domain (Webfinger for Zitadel) ---
      "${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        locations."/.well-known/webfinger".extraConfig = ''
          add_header Content-Type application/jrd+json;
          return 200 '{"subject":"acct:info@${baseDomain}","links":[{"rel":"http://openid.net/specs/connect/1.0/issuer","href":"https://${nodes.nix-keycloak.sub}.${baseDomain}"}]}';
        '';
      };

      "default" = {
        default = true; # This makes it the catch-all
        rejectSSL = true; # Drops SSL handshakes for unknown domains
        locations."/".extraConfig = ''
          return 444; # "Connection Closed Without Response"
        '';
      };
      "openwrt.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        extraConfig = lanOnly;
        locations."/".proxyPass = "http://10.60.1.1";
      };

      # --- AdGuard ---
      "${nodes.nix-adguard.hostname}.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        extraConfig = lanOnly;
        locations."/".proxyPass = "http://${nodes.nix-adguard.ip}:${toString nodes.nix-adguard.port}";
      };
      "${nodes.nix-keycloak.sub}.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;

        locations."/" = commonProxy // {
          proxyPass = "http://${nodes.nix-keycloak.ip}:${toString nodes.nix-keycloak.port}";
          extraConfig = commonProxy.extraConfig + "proxy_set_header X-Forwarded-Port 443;";
        };
      };
      # --- Collabora Online ---
      "collabora.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;

        # Static files
        locations."^~ /browser" = commonProxy // {
          proxyPass = "http://${nodes.nix-opencloud.ip}:9980";
        };

        # WOPI discovery URL
        locations."^~ /hosting/discovery" = commonProxy // {
          proxyPass = "http://${nodes.nix-opencloud.ip}:9980";
        };

        # Capabilities
        locations."^~ /hosting/capabilities" = commonProxy // {
          proxyPass = "http://${nodes.nix-opencloud.ip}:9980";
        };

        # Main websocket - This handles the wss:// connection you're seeing fail
        locations."~ ^/cool/(.*)/ws$" = {
            proxyPass = "http://${nodes.nix-opencloud.ip}:9980";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "Upgrade";
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto https;
              proxy_read_timeout 36000s;
            '';
          };

        # Download, presentation and image upload
        locations."~ ^/cool" = commonProxy // {
          proxyPass = "http://${nodes.nix-opencloud.ip}:9980";
        };

        # Admin Console websocket
        locations."^~ /cool/adminws" = commonProxy // {
          proxyPass = "http://${nodes.nix-opencloud.ip}:9980";
          extraConfig = commonProxy.extraConfig + ''
            proxy_set_header Upgrade ''$http_upgrade;
            proxy_set_header Connection "Upgrade";
            proxy_read_timeout 36000s;
          '';
        };

        # Root fallback
        locations."/" = commonProxy // {
          proxyPass = "http://${nodes.nix-opencloud.ip}:9980";
          extraConfig = commonProxy.extraConfig + ''
            proxy_hide_header X-Frame-Options;
          '';
        };
      };
      "${nodes.nix-listmonk.sub}.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        http2 = false;
        # Since this contains admin controls, you might want to wrap this in lanOnly
        # if you only want to manage it via VPN, or leave it public for subscribers.
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Host $host;
          proxy_set_header X-Forwarded-Port $server_port;
        '';

        locations."/" = commonProxy // {
          proxyPass = "http://${nodes.nix-listmonk.ip}:${toString nodes.nix-listmonk.port}";
        };

        # Optimization for media/template uploads
        locations."/uploads" = {
          proxyPass = "http://${nodes.nix-listmonk.ip}:${toString nodes.nix-listmonk.port}";
          extraConfig = ''
            client_max_body_size 100M;
          '';
        };
      };
      # --- Zitadel ---
      "${nodes.nix-zitadel.hostname}.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        http2 = true;
        locations."/" = commonProxy // {
          proxyPass = "http://${nodes.nix-zitadel.ip}:8081";
          # Notice the ''$ to escape Nginx variables from Nix interpolation
          extraConfig = commonProxy.extraConfig + "proxy_set_header X-Forwarded-Port 443;";
        };
      };
      "${nodes.nix-influx.hostname}.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        http2 = true;
        locations."/" = commonProxy // {
          proxyPass = "http://${nodes.nix-influx.ip}:${toString nodes.nix-influx.port}";
          # Notice the ''$ to escape Nginx variables from Nix interpolation
          extraConfig = commonProxy.extraConfig + "proxy_set_header X-Forwarded-Port 443;";
        };
      };
      "${nodes.nix-grafana.hostname}.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        http2 = true;
        locations."/" = commonProxy // {
          proxyPass = "http://${nodes.nix-grafana.ip}:${toString nodes.nix-grafana.port}";
          # Notice the ''$ to escape Nginx variables from Nix interpolation
          extraConfig = commonProxy.extraConfig + "proxy_set_header X-Forwarded-Port 443;";
        };
      };

      "${nodes.nix-immich.sub}.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        # Immich can handle large photo/video uploads, so we must raise the limit
        globalRedirect = null;
        locations."/" = commonProxy // {
          proxyPass = "http://${nodes.nix-immich.ip}:${toString nodes.nix-immich.port}";
          proxyWebsockets = true;
          extraConfig = commonProxy.extraConfig + ''
            client_max_body_size 50000M;
            proxy_read_timeout 600s;
            proxy_send_timeout 600s;
            send_timeout 600s;
          '';
        };
      };

      # --- HedgeDoc ---
      "${nodes.nix-hedgedoc.hostname}.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        http2 = true;
        locations."/" = commonProxy // {
          proxyPass = "http://${nodes.nix-hedgedoc.ip}:${toString nodes.nix-hedgedoc.port}";
        };
        locations."/socket.io/" = commonProxy // {
          proxyPass = "http://${nodes.nix-hedgedoc.ip}:${toString nodes.nix-hedgedoc.port}";
          extraConfig = commonProxy.extraConfig + ''
            proxy_set_header Upgrade ''$http_upgrade;
            proxy_set_header Connection ''$connection_upgrade;
          '';
        };
      };

      # --- Paperless ---
      "${nodes.nix-paperless.hostname}.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        extraConfig = lanOnly;
        locations."/" = commonProxy // {
          proxyPass = "http://${nodes.nix-paperless.ip}:${toString nodes.nix-paperless.port}";
        };
      };

      # --- Home Assistant ---
      "${nodes.nix-homeassistant.hostname}.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        extraConfig = lanOnly;
        locations."/" = commonProxy // {
          proxyPass = "http://${nodes.nix-homeassistant.ip}:${toString nodes.nix-homeassistant.port}";
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
        locations."/login" = commonProxy // {
          return = "301 https://${nodes.nix-homeassistant.hostname}.${baseDomain}/auth/oidc/welcome";
        };
      };
      "musicassistant.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        extraConfig = lanOnly;
        locations."/" = commonProxy // {
          proxyPass = "http://${nodes.nix-homeassistant.ip}:8095";
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
      };

      # --- Headscale ---
      "${nodes.nix-headscale.hostname}.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        locations."/" = commonProxy // {
          proxyPass = "http://${nodes.nix-headscale.ip}:8080";
          extraConfig = commonProxy.extraConfig + ''
            proxy_buffering off;
            add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;
          '';
        };
        locations."/admin/" = commonProxy // {
          proxyPass = "http://${nodes.nix-headscale.ip}:3000/admin/";
        };
        locations."/admin".extraConfig = "return 301 /admin/ ;";
      };
      "${nodes.nix-opencloud.hostname}.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        http2 = false;

        # These settings apply to the entire Virtual Host (Server block)
        extraConfig = ''
          client_max_body_size 10M;
          proxy_buffering off;
          proxy_request_buffering off;
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
          keepalive_requests 100000;
          keepalive_timeout 5m;
          http2_max_concurrent_streams 512;
          proxy_next_upstream off;
        '';

        locations."/" = {
          proxyPass = "http://${nodes.nix-opencloud.ip}:${toString nodes.nix-opencloud.port}";
          proxyWebsockets = true;
          # We use the commonProxy headers here to avoid repetition
          extraConfig = commonProxy.extraConfig;
        };
      };

      # --- External Hosts (Non-Containers) ---
      "pve1.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        extraConfig = lanOnly;
        locations."/".proxyPass = "https://10.60.0.3:8006/";
      };

      "${nodes.nix-unifi-controller.hostname}.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        extraConfig = lanOnly;
        locations."/" = commonProxy // {
          proxyPass = "https://${nodes.nix-unifi-controller.ip}:${toString nodes.nix-unifi-controller.port}";
        };
      };
    };
  };

  # ... (ACME and Firewall remain the same) ...
  security.acme = {
    acceptTerms = true;
    defaults.group = "nginx"; # This allows the nginx group to read the certs
    defaults.enableDebugLogs = true;
    certs."${baseDomain}" = {
      extraDomainNames = [ "*.${baseDomain}" ];
      dnsProvider = "inwx";
      email = "acme@hackler.io";

      # This ensures Nginx reloads whenever the certificate is renewed
      reloadServices = [ "nginx.service" ];

      environmentFile = config.sops.secrets."acme-inwx-env".path;
      dnsPropagationCheck = false;
    };
  };
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
