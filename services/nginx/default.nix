{
  config,
  pkgs,
  lib,
  nodes,
  baseDomain,
  ...
}:

let
  # --- MAINTENANCE MODE ---
  # Set to true to take every virtual host down and serve a 503 + notice
  # page instead. Set back to false to restore normal proxying.
  # Nothing else in this file needs to change.
  maintenanceMode = true;

  # Public IP(s) that should bypass the maintenance page (e.g. your own
  # connection, for testing). Leave empty to show the notice to everyone.
  maintenanceBypassIPs = [
    # "203.0.113.5"
  ];

  maintenanceHtml = pkgs.writeTextDir "maintenance.html" ''
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Crect width='24' height='24' rx='5' fill='%23141721'/%3E%3Cpath d='M12 3 21 19H3Z' fill='%23fbbf24'/%3E%3Crect x='11' y='9' width='2' height='5' rx='1' fill='%23141721'/%3E%3Crect x='11' y='15.5' width='2' height='2' rx='1' fill='%23141721'/%3E%3C/svg%3E" />
      <title>Down for maintenance</title>
      <style>
        :root {
          color-scheme: dark;
        }
        * { box-sizing: border-box; }
        html, body {
          height: 100%;
          margin: 0;
        }
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
          background: #0b0e14;
          color: #e6e9ef;
          display: flex;
          align-items: center;
          justify-content: center;
          overflow: hidden;
          position: relative;
        }

        /* Animated gradient blobs drifting in the background */
        .blob {
          position: absolute;
          border-radius: 50%;
          filter: blur(80px);
          opacity: 0.55;
          will-change: transform;
        }
        .blob.one {
          width: 480px;
          height: 480px;
          top: -120px;
          left: -100px;
          background: radial-gradient(circle at 30% 30%, #6366f1, transparent 70%);
          animation: drift1 18s ease-in-out infinite;
        }
        .blob.two {
          width: 420px;
          height: 420px;
          bottom: -140px;
          right: -100px;
          background: radial-gradient(circle at 60% 60%, #ec4899, transparent 70%);
          animation: drift2 22s ease-in-out infinite;
        }
        .blob.three {
          width: 360px;
          height: 360px;
          top: 40%;
          left: 60%;
          background: radial-gradient(circle at 50% 50%, #22d3ee, transparent 70%);
          animation: drift3 26s ease-in-out infinite;
        }

        @keyframes drift1 {
          0%, 100% { transform: translate(0, 0) scale(1); }
          50% { transform: translate(60px, 40px) scale(1.1); }
        }
        @keyframes drift2 {
          0%, 100% { transform: translate(0, 0) scale(1); }
          50% { transform: translate(-50px, -30px) scale(1.15); }
        }
        @keyframes drift3 {
          0%, 100% { transform: translate(0, 0) scale(1); }
          50% { transform: translate(-40px, 50px) scale(0.9); }
        }

        /* Subtle grain/noise overlay for depth */
        .grain {
          position: absolute;
          inset: 0;
          background-image: radial-gradient(rgba(255,255,255,0.035) 1px, transparent 1px);
          background-size: 3px 3px;
          pointer-events: none;
        }

        .card {
          position: relative;
          z-index: 2;
          max-width: 560px;
          width: calc(100% - 48px);
          text-align: center;
          padding: 48px 40px;
          border-radius: 24px;
          background: rgba(20, 23, 33, 0.55);
          border: 1px solid rgba(255, 255, 255, 0.08);
          backdrop-filter: blur(18px);
          -webkit-backdrop-filter: blur(18px);
          box-shadow: 0 20px 60px rgba(0, 0, 0, 0.45);
          animation: rise 0.7s cubic-bezier(0.16, 1, 0.3, 1) both;
        }

        @keyframes rise {
          from { opacity: 0; transform: translateY(24px); }
          to { opacity: 1; transform: translateY(0); }
        }

        .icon-wrap {
          width: 76px;
          height: 76px;
          margin: 0 auto 24px;
          position: relative;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .icon-ring {
          position: absolute;
          inset: 0;
          border-radius: 50%;
          border: 2px solid transparent;
          border-top-color: #fbbf24;
          border-right-color: #fbbf24;
          animation: spin 1.6s linear infinite;
        }
        .icon-ring.slow {
          inset: -10px;
          border-top-color: transparent;
          border-right-color: transparent;
          border-bottom-color: rgba(249, 115, 22, 0.6);
          border-left-color: rgba(249, 115, 22, 0.6);
          animation: spinReverse 3.2s linear infinite;
        }
        @keyframes spin {
          to { transform: rotate(360deg); }
        }
        @keyframes spinReverse {
          to { transform: rotate(-360deg); }
        }
        .icon-wrap svg {
          width: 40px;
          height: 40px;
          animation: pulseIcon 2.4s ease-in-out infinite;
        }
        @keyframes pulseIcon {
          0%, 100% { transform: scale(1) rotate(0deg); opacity: 1; }
          50% { transform: scale(1.08) rotate(-2deg); opacity: 0.9; }
        }
        .stripe {
          animation: stripeMove 1.2s linear infinite;
        }
        @keyframes stripeMove {
          0% { stroke-dashoffset: 0; }
          100% { stroke-dashoffset: -16; }
        }

        h1 {
          margin: 0 0 12px;
          font-size: 28px;
          font-weight: 650;
          letter-spacing: -0.02em;
          background: linear-gradient(90deg, #e6e9ef, #fbbf24 60%, #f97316);
          -webkit-background-clip: text;
          background-clip: text;
          color: transparent;
        }

        p {
          margin: 0 0 28px;
          font-size: 15px;
          line-height: 1.6;
          color: #9aa1b1;
        }

        .status {
          display: inline-flex;
          align-items: center;
          gap: 8px;
          padding: 8px 16px;
          border-radius: 999px;
          background: rgba(251, 191, 36, 0.12);
          border: 1px solid rgba(251, 191, 36, 0.25);
          font-size: 13px;
          font-weight: 500;
          color: #fde68a;
        }

        .dot {
          width: 8px;
          height: 8px;
          border-radius: 50%;
          background: #fbbf24;
          animation: blink 1.4s ease-in-out infinite;
          box-shadow: 0 0 0 rgba(251, 191, 36, 0.6);
        }
        @keyframes blink {
          0%, 100% { opacity: 0.35; box-shadow: 0 0 0 0 rgba(251, 191, 36, 0.5); }
          50% { opacity: 1; box-shadow: 0 0 8px 2px rgba(251, 191, 36, 0.5); }
        }

        .hazard-strip {
          display: block;
          width: 100%;
          height: 14px;
          margin-top: 28px;
          border-radius: 6px;
          overflow: hidden;
          box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.08);
        }

        @media (prefers-reduced-motion: reduce) {
          .blob, .icon-ring, .icon-wrap svg, .dot, .stripe, .card {
            animation: none !important;
          }
        }
      </style>
    </head>
    <body>
      <div class="blob one"></div>
      <div class="blob two"></div>
      <div class="blob three"></div>
      <div class="grain"></div>

      <main class="card">
        <div class="icon-wrap">
          <div class="icon-ring"></div>
          <div class="icon-ring slow"></div>
          <svg viewBox="0 0 24 24" fill="none" stroke="#fbbf24" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
            <path d="M12 2.5 22.5 20.5H1.5Z" fill="rgba(251, 191, 36, 0.12)"></path>
            <line x1="12" y1="9" x2="12" y2="14"></line>
            <line x1="12" y1="17" x2="12.01" y2="17"></line>
          </svg>
        </div>

        <h1>Under construction</h1>
        <p>This service is offline for a bit of scheduled maintenance.<br />No action needed on your end — just check back shortly.</p>

        <span class="status"><span class="dot"></span>Maintenance in progress</span>

        <svg class="hazard-strip" viewBox="0 0 400 16" preserveAspectRatio="none" aria-hidden="true">
          <defs>
            <pattern id="hazard" width="16" height="16" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
              <rect width="16" height="16" fill="#141721"></rect>
              <rect width="8" height="16" fill="#fbbf24"></rect>
            </pattern>
          </defs>
          <rect class="stripe" width="400" height="16" fill="url(#hazard)"></rect>
        </svg>

        <div class="bar-track"><div class="bar-fill"></div></div>
      </main>
    </body>
    </html>
  '';

  maintenanceLocations = {
    # Catch-all: decide whether to trigger the maintenance page, then hand
    # off to /maintenance.html via error_page (an internal redirect).
    "/" = {
      extraConfig = ''
        set $maintenance_mode 1;
        ${lib.concatMapStrings (ip: ''
          if ($remote_addr = ${ip}) { set $maintenance_mode 0; }
        '') maintenanceBypassIPs}
        if ($maintenance_mode = 1) { return 503; }
        error_page 503 /maintenance.html;
      '';
    };
    # Dedicated location for the error page itself. Must be separate from
    # "/" and marked internal — otherwise the error_page redirect above
    # lands right back in the 503-returning "/" block and loops, which is
    # why nginx was falling back to its plain-text default 503 page.
    "= /maintenance.html" = {
      root = maintenanceHtml;
      extraConfig = "internal;";
    };
  };

  # Replace every location in every vhost with the maintenance page,
  # leaving hostnames, certs, forceSSL, etc. exactly as declared below.
  applyMaintenance =
    vhosts:
    lib.mapAttrs (
      name: vhost:
      if name == "default" then
        vhost # keep the catch-all/reject-SSL block as-is
      else
        vhost // { locations = maintenanceLocations; }
    ) vhosts;

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
    package = pkgs.nginxMainline;
    appendHttpConfig = ''
      map ''$http_upgrade ''$connection_upgrade {
          default upgrade;
          # Escaped empty string for Nginx
          '''       close;
      }
    '';

    virtualHosts =
      let
        vhosts = {
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
          # --- Nixarr User Facing (Public + OIDC Plugin) ---
          "stream.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;
            locations."/" = commonProxy // {
              proxyPass = "http://10.60.1.31:8096";
              # Jellyfin is sensitive to these for OIDC and streaming
              extraConfig = commonProxy.extraConfig + ''
                proxy_set_header X-Forwarded-Proto $scheme;
                proxy_buffering off;
              '';
            };
          };
          "sure.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;
            extraConfig = lanOnly;
            locations."/" = commonProxy // {
              proxyPass = "http://10.60.1.37:3000";
              # Jellyfin is sensitive to these for OIDC and streaming
              extraConfig = commonProxy.extraConfig + ''
                proxy_set_header X-Forwarded-Proto $scheme;
                proxy_buffering off;
              '';
            };
          };

          # --- Nixarr Management (LAN/VPN Only) ---
          "radarr.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;
            extraConfig = lanOnly;
            locations."/".proxyPass = "http://10.60.1.31:7878";
          };

          "profilarr.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;
            extraConfig = lanOnly;
            locations."/".proxyPass = "http://10.60.1.31:6868";
          };

          "sonarr.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;
            extraConfig = lanOnly;
            locations."/".proxyPass = "http://10.60.1.31:8989";
          };

          "sabnzbd.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;
            extraConfig = lanOnly;
            locations."/".proxyPass = "http://10.60.1.31:6336";
          };
          "bindery.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;
            extraConfig = lanOnly;
            locations."/" = commonProxy // {
              proxyPass = "http://10.60.1.31:8787";
            };
          };

          "shelfmark.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;
            locations."/" = commonProxy // {
              proxyPass = "http://10.60.1.31:8084";
            };
          };
          "books.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;
            extraConfig = ''
              client_max_body_size 500M;   # BookDrop / web uploads
            '';
            locations."/" = commonProxy // {
              proxyPass = "http://10.60.1.31:6060";
              extraConfig = commonProxy.extraConfig + ''
                proxy_buffering off;       # smoother epub/audio streaming
                proxy_read_timeout 600s;
                proxy_send_timeout 600s;
              '';
            };
          };

          "lidarr.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;
            extraConfig = lanOnly;
            locations."/".proxyPass = "http://10.60.1.31:8686";
          };

          "bitmagnet.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;
            extraConfig = lanOnly;
            locations."/".proxyPass = "http://10.60.1.31:3333";
          };

          "aurral.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;
            extraConfig = lanOnly;
            locations."/".proxyPass = "http://10.60.1.31:3001";
          };

          "prowlarr.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;
            extraConfig = lanOnly;
            locations."/".proxyPass = "http://10.60.1.31:9696";
          };

          "transmission.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;
            extraConfig = lanOnly;
            locations."/" = commonProxy // {
              proxyPass = "http://10.60.1.31:9091";
            };
          };

          # Optional: Subtitle management
          "bazarr.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;
            extraConfig = lanOnly;
            locations."/".proxyPass = "http://10.60.1.31:6767";
          };
          "requests.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;
            # NO lanOnly here - we want this accessible!
            locations."/" = commonProxy // {
              proxyPass = "http://10.60.1.31:5055";
            };
          };
          "musicrequests.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;
            # extraConfig = lanOnly;
            locations."/" = commonProxy // {
              proxyPass = "http://10.60.1.31:8688";
            };
          };
          "openwrt.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;
            extraConfig = lanOnly;
            locations."/".proxyPass = "http://10.60.1.1";
          };
          "${nodes.nix-commafeed.sub}.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;

            locations."/" = commonProxy // {
              proxyPass = "http://${nodes.nix-commafeed.ip}:${toString nodes.nix-commafeed.port}";
              extraConfig = commonProxy.extraConfig + ''
                proxy_set_header X-Forwarded-Proto $scheme;
                proxy_set_header X-Forwarded-Port 443;

                # Standard optimization for RSS feed content
                client_max_body_size 20M;
              '';
            };
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
          "collabora.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;

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

            # This regex handles both COOL and Admin WebSockets
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

            # These match the "top level" settings in the Immich Doc
            extraConfig = ''
              client_max_body_size 50000M;
              proxy_request_buffering off;
              client_body_buffer_size 1024k;
            '';

            locations."/" = {
              proxyPass = "http://${nodes.nix-immich.ip}:${toString nodes.nix-immich.port}";

              # This is the "enable websockets" part of the doc
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

          "matter.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;
            extraConfig = lanOnly;
            locations."/" = commonProxy // {
              proxyPass = "http://${nodes.nix-homeassistant.ip}:5580";
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
          "otbr.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;
            extraConfig = lanOnly;
            locations."/" = commonProxy // {
              proxyPass = "http://${nodes.nix-homeassistant.ip}:8082";
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
          "musicassistant.${baseDomain}" = {
            useACMEHost = baseDomain;
            forceSSL = true;
            extraConfig = lanOnly;
            locations."/" = commonProxy // {
              proxyPass = "http://${nodes.nix-homeassistant.ip}:8095";
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
      in
      if maintenanceMode then applyMaintenance vhosts else vhosts;
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
