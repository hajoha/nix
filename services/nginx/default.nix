{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (config.homelab) nodes;
  baseDomain = config.homelab.domain;

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

  # A TLS vhost on the wildcard cert. `lan = true` restricts it to LAN/VPN;
  # its own `extraConfig` is appended after the allow/deny rules.
  vhost =
    {
      lan ? false,
      ...
    }@args:
    let
      extra = (if lan then lanOnly else "") + (args.extraConfig or "");
    in
    {
      useACMEHost = baseDomain;
      forceSSL = true;
    }
    // removeAttrs args [
      "lan"
      "extraConfig"
    ]
    // lib.optionalAttrs (extra != "") { extraConfig = extra; };

  # A location proxying to `to` with the shared headers + websockets;
  # `extra` is appended to the shared headers.
  proxy =
    to: extra:
    commonProxy
    // {
      proxyPass = to;
    }
    // lib.optionalAttrs (extra != "") { extraConfig = commonProxy.extraConfig + extra; };

  # Nixarr's apps all live on nix-arr, one port each.
  arr = port: "http://${nodes.nix-arr.ip}:${toString port}";
  hass = port: "http://${nodes.nix-homeassistant.ip}:${toString port}";

  # LAN-only *arr UIs that are proxied without the shared headers.
  arrLanPlain = {
    radarr = 7878;
    profilarr = 6868;
    sonarr = 8989;
    sabnzbd = 6336;
    lidarr = 8686;
    bitmagnet = 3333;
    aurral = 3001;
    prowlarr = 9696;
    bazarr = 6767; # subtitles
  };

  # Home Assistant add-ons (matter, otbr) behind LAN-only vhosts.
  hassAddon =
    port:
    vhost {
      lan = true;
      locations."/" = commonProxy // {
        proxyPass = hass port;
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host $server_name;
          proxy_redirect http:// https://;
          proxy_buffering off;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        '';
      };
    };
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
    package = pkgs.nginxMainline;
    appendHttpConfig = ''
      map ''$http_upgrade ''$connection_upgrade {
          default upgrade;
          # Escaped empty string for Nginx
          '''       close;
      }
    '';

    virtualHosts =
      lib.mapAttrs' (
        name: port:
        lib.nameValuePair "${name}.${baseDomain}" (vhost {
          lan = true;
          locations."/".proxyPass = arr port;
        })
      ) arrLanPlain
      // {
        # --- Root domain: OIDC webfinger pointing at Keycloak ---
        "${baseDomain}" = vhost {
          locations."/.well-known/webfinger".extraConfig = ''
            add_header Content-Type application/jrd+json;
            return 200 '{"subject":"acct:info@${baseDomain}","links":[{"rel":"http://openid.net/specs/connect/1.0/issuer","href":"${nodes.nix-keycloak.url}"}]}';
          '';
        };

        "default" = {
          default = true; # catch-all
          rejectSSL = true; # drop TLS handshakes for unknown names
          locations."/".extraConfig = ''
            return 444; # "Connection Closed Without Response"
          '';
        };

        # --- Nixarr: public ---
        # Jellyfin is sensitive to these for OIDC and streaming.
        "stream.${baseDomain}" = vhost {
          locations."/" = proxy (arr 8096) ''
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_buffering off;
          '';
        };
        "audiobooks.${baseDomain}" = vhost { locations."/" = proxy (arr 9292) ""; };
        "shelfmark.${baseDomain}" = vhost { locations."/" = proxy (arr 8084) ""; };
        "requests.${baseDomain}" = vhost { locations."/" = proxy (arr 5055) ""; };
        "musicrequests.${baseDomain}" = vhost { locations."/" = proxy (arr 8688) ""; };
        "books.${baseDomain}" = vhost {
          extraConfig = ''
            client_max_body_size 500M;   # BookDrop / web uploads
          '';
          locations."/" = proxy (arr 6060) ''
            proxy_buffering off;       # smoother epub/audio streaming
            proxy_read_timeout 600s;
            proxy_send_timeout 600s;
          '';
        };

        # --- Nixarr: LAN/VPN only (plus arrLanPlain above) ---
        "bindery.${baseDomain}" = vhost {
          lan = true;
          locations."/" = proxy (arr 8787) "";
        };
        "transmission.${baseDomain}" = vhost {
          lan = true;
          locations."/" = proxy (arr 9091) "";
        };

        "${nodes.nix-sure.fqdn}" = vhost {
          lan = true;
          locations."/" = proxy nodes.nix-sure.addr ''
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_buffering off;
          '';
        };

        "${nodes.nix-commafeed.fqdn}" = vhost {
          locations."/" = proxy nodes.nix-commafeed.addr ''
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Port 443;

            # Standard optimization for RSS feed content
            client_max_body_size 20M;
          '';
        };

        "${nodes.nix-adguard.fqdn}" = vhost {
          lan = true;
          locations."/".proxyPass = nodes.nix-adguard.addr;
        };

        "${nodes.nix-keycloak.fqdn}" = vhost {
          locations."/" = proxy nodes.nix-keycloak.addr "proxy_set_header X-Forwarded-Port 443;";
        };

        "collabora.${baseDomain}" = vhost {
          locations."/" = {
            proxyPass = "http://${nodes.nix-opencloud.ip}:9980";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto https; # Force https here
              proxy_hide_header X-Frame-Options;
            '';
          };
          # COOL and admin websockets
          locations."~ ^/(cool|browser)/.*ws$" = {
            proxyPass = "http://${nodes.nix-opencloud.ip}:9980";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "Upgrade";
              proxy_set_header Host $host;
              proxy_read_timeout 36000s;
            '';
          };
        };

        # Public for subscribers; contains admin controls too.
        "${nodes.nix-listmonk.fqdn}" = vhost {
          http2 = false;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Port $server_port;
          '';
          locations."/" = proxy nodes.nix-listmonk.addr "";
          # media/template uploads
          locations."/uploads" = {
            proxyPass = nodes.nix-listmonk.addr;
            extraConfig = ''
              client_max_body_size 100M;
            '';
          };
        };

        "${nodes.nix-influx.fqdn}" = vhost {
          http2 = true;
          locations."/" = proxy nodes.nix-influx.addr "proxy_set_header X-Forwarded-Port 443;";
        };
        "${nodes.nix-grafana.fqdn}" = vhost {
          http2 = true;
          locations."/" = proxy nodes.nix-grafana.addr "proxy_set_header X-Forwarded-Port 443;";
        };

        # Settings follow the Immich reverse-proxy docs.
        "${nodes.nix-immich.fqdn}" = vhost {
          extraConfig = ''
            client_max_body_size 50000M;
            proxy_request_buffering off;
            client_body_buffer_size 1024k;
          '';
          locations."/" = {
            proxyPass = nodes.nix-immich.addr;
            proxyWebsockets = true;
            extraConfig = ''
              # These are the 4 headers the doc says MUST be forwarded
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;

              # Timeouts from the doc
              proxy_read_timeout 600s;
              proxy_send_timeout 600s;
              send_timeout 600s;

              # The doc uses proxy_redirect off
              proxy_redirect off;
            '';
          };
        };

        "${nodes.nix-hedgedoc.fqdn}" = vhost {
          http2 = true;
          locations."/" = proxy nodes.nix-hedgedoc.addr "";
          locations."/socket.io/" = proxy nodes.nix-hedgedoc.addr ''
            proxy_set_header Upgrade ''$http_upgrade;
            proxy_set_header Connection ''$connection_upgrade;
          '';
        };

        "${nodes.nix-paperless.fqdn}" = vhost {
          lan = true;
          locations."/" = proxy nodes.nix-paperless.addr "";
        };

        # --- Home Assistant + add-ons ---
        "${nodes.nix-homeassistant.fqdn}" = vhost {
          lan = true;
          locations."/" = commonProxy // {
            proxyPass = nodes.nix-homeassistant.addr;
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
            return = "301 ${nodes.nix-homeassistant.url}/auth/oidc/welcome";
          };
        };
        "matter.${baseDomain}" = hassAddon 5580;
        "otbr.${baseDomain}" = hassAddon 8082;
        "musicassistant.${baseDomain}" = vhost {
          lan = true;
          locations."/" = commonProxy // {
            proxyPass = hass 8095;
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Host $server_name;
              proxy_redirect http:// https://;
              proxy_buffering off;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_read_timeout 3600s;
              proxy_send_timeout 3600s;
              add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;
            '';
          };
        };

        # --- atproto PDS (Tranquil) ---
        # Must stay public (no lanOnly): relays, appviews and OAuth clients such as
        # tangled.org reach it from the internet. User handles are subdomains
        # (<name>.pds.<domain>) and resolve via /.well-known/atproto-did on the
        # same backend, hence the wildcard alias.
        "${nodes.nix-tranquil.fqdn}" = vhost {
          serverAliases = [ "*.${nodes.nix-tranquil.fqdn}" ];
          extraConfig = ''
            # Blob uploads and repo imports (Tranquil accepts imports up to 1 GiB).
            client_max_body_size 1G;
            proxy_request_buffering off;
          '';
          locations."/" = proxy nodes.nix-tranquil.addr ''
            # com.atproto.sync.subscribeRepos is a long-lived websocket that
            # relays hold open; a quiet single-user PDS would hit nginx's
            # default 60s read timeout and get disconnected over and over.
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
          '';
        };

        # --- Headscale ---
        "${nodes.nix-headscale.fqdn}" = vhost {
          locations."/" = proxy "http://${nodes.nix-headscale.ip}:8080" ''
            proxy_buffering off;
            add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;
          '';
          locations."/admin/" = proxy "http://${nodes.nix-headscale.ip}:3000/admin/" "";
          locations."/admin".extraConfig = "return 301 /admin/ ;";
        };

        "${nodes.nix-opencloud.fqdn}" = vhost {
          http2 = false;
          extraConfig = ''
            client_max_body_size 50000M;
            proxy_buffering off;
            proxy_request_buffering off;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
            keepalive_requests 100000;
            keepalive_timeout 5m;
            http2_max_concurrent_streams 512;
            proxy_set_header X-Forwarded-Port 443;
            proxy_next_upstream off;
          '';
          locations."/" = {
            proxyPass = nodes.nix-opencloud.addr;
            proxyWebsockets = true;
            inherit (commonProxy) extraConfig;
          };
        };

        # --- Non-container hosts ---
        "openwrt.${baseDomain}" = vhost {
          lan = true;
          locations."/".proxyPass = "http://10.60.1.1";
        };
        "pve1.${baseDomain}" = vhost {
          lan = true;
          locations."/".proxyPass = "https://10.60.0.3:8006/";
        };
        "${nodes.nix-unifi-controller.fqdn}" = vhost {
          lan = true;
          locations."/" =
            proxy "https://${nodes.nix-unifi-controller.ip}:${toString nodes.nix-unifi-controller.port}" "";
        };
      };
  };

  # ... (ACME and Firewall remain the same) ...
  security.acme = {
    acceptTerms = true;
    defaults.group = "nginx"; # This allows the nginx group to read the certs
    defaults.enableDebugLogs = true;
    certs."${baseDomain}" = {
      extraDomainNames = [
        "*.${baseDomain}"
        "*.${nodes.nix-tranquil.fqdn}"
      ];
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
