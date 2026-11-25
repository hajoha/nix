# Notifications and an outside-in check of the homelab, on the VPS
# (independent of the homelab, so it still alerts when home is down).
#
# Everything here lives under monitor.<domain> (DNS: monitor.<domain> and
# *.monitor.<domain> point to the VPS):
#
#   internet ──443──▶ Traefik (Let's Encrypt, HTTP-01, one cert per name)
#     notify.monitor.<domain>  ──▶ ntfy  127.0.0.1:2586
#     status.monitor.<domain>  ──▶ Gatus 127.0.0.1:8080 (basic auth, admin login)
#     monitor.<domain>         ──▶ redirect to status.
#
#   Grafana (homelab) ──webhook──▶ notify.monitor.<domain>/homelab  alerts from inside
#   Gatus (here)      ──────────▶ ntfy, topic homelab        alerts from outside:
#     public vhosts (https), home over WireGuard (ping), nix-loki / nix-thanos
#     (tcp), ntfy itself
#
# ntfy: nobody may read or write without an account (deny-all). The users
# and the token come from sops (hosts/hetzner-vps-01/secrets.enc.yaml):
#
#   ntfy:
#     admin-hash:   bcrypt of your password      (phone app / web login)
#     alerts-hash:  bcrypt of a random password  (user "alerts", never used)
#     alerts-token: tk_…                         (Grafana + Gatus publish)
#
#   nix shell nixpkgs#ntfy-sh -c ntfy user hash        # prints a bcrypt hash
#   echo "tk_$(tr -dc a-z0-9 </dev/urandom | head -c 29)"
#
# Subscribe in the ntfy app: server https://notify.monitor.<domain>, topic
# "homelab", log in as `adminUser`. The status page takes the same login.
{
  config,
  lib,
  baseDomain,
  publicVhosts,
  inventory,
  ...
}:
let
  inherit (inventory) nodes;

  zone = "monitor.${baseDomain}";
  fqdn = "notify.${zone}";
  statusFqdn = "status.${zone}";
  ntfyListen = "127.0.0.1:2586";
  gatusPort = 8080;
  topic = "homelab";
  adminUser = "hajoha";

  wgPeers = lib.importJSON ./wireguard-peers.json;
  homeRouter = (lib.findFirst (p: p.name == "home-openwrt") null wgPeers).ip;

  secret = name: config.sops.placeholder."ntfy/${name}";

  # Gatus: every endpoint alerts through ntfy after 3 failed checks
  alerts = [ { type = "ntfy"; } ];
  https = group: name: url: extra: {
    inherit name group url alerts;
    interval = "1m";
    client.timeout = "10s";
    conditions = [
      # same rule as the http_up probes: anything below 500 means "it answers"
      "[STATUS] < 500"
      "[CERTIFICATE_EXPIRATION] > 168h"
    ]
    ++ extra;
  };
  connected = group: name: url: {
    inherit name group url alerts;
    interval = "30s";
    conditions = [ "[CONNECTED] == true" ];
  };
in
{
  sops.secrets = {
    "ntfy/admin-hash" = { };
    "ntfy/alerts-hash" = { };
    "ntfy/alerts-token" = { };
  };

  # systemd EnvironmentFile: no $-expansion, single quotes are stripped
  sops.templates."ntfy.env".content = ''
    NTFY_AUTH_USERS='${adminUser}:${secret "admin-hash"}:admin,alerts:${secret "alerts-hash"}:user'
    NTFY_AUTH_ACCESS='alerts:${topic}:wo'
    NTFY_AUTH_TOKENS='alerts:${secret "alerts-token"}:grafana-gatus'
  '';
  sops.templates."gatus.env".content = ''
    NTFY_TOKEN=${secret "alerts-token"}
  '';
  # htpasswd for the status page: the ntfy admin's bcrypt hash, one password
  sops.templates."traefik-status-users" = {
    owner = "traefik";
    content = ''
      ${adminUser}:${secret "admin-hash"}
    '';
  };

  # --- ntfy ----------------------------------------------------------------

  services.ntfy-sh = {
    enable = true;
    environmentFile = config.sops.templates."ntfy.env".path;
    settings = {
      base-url = "https://${fqdn}";
      listen-http = ntfyListen;
      behind-proxy = true; # client IPs from Traefik's X-Forwarded-For (rate limits)
      auth-default-access = "deny-all";
      enable-login = true;
      enable-signup = false;
      # no web app: only the phone app and the API (curl, Grafana, Gatus)
      web-root = "disable";
      # keep messages for clients that were offline
      cache-duration = "72h";
      attachment-total-size-limit = "1G";
      attachment-file-size-limit = "15M";
      # iOS only gets instant pushes through ntfy.sh's relay; uncomment if
      # you use the iOS app (sends the topic hash to ntfy.sh, no content):
      # upstream-base-url = "https://ntfy.sh";
    };
  };

  # --- Traefik -------------------------------------------------------------

  services.traefik = {
    enable = true;
    staticConfigOptions = {
      global = {
        checkNewVersion = false;
        sendAnonymousUsage = false;
      };
      log.level = "WARN";
      accessLog = { }; # to the journal -> Loki (instance hetzner-vps-01)

      entryPoints = {
        web = {
          address = ":80";
          # the ACME challenge is answered before this redirect
          http.redirections.entryPoint = {
            to = "websecure";
            scheme = "https";
          };
        };
        websecure.address = ":443";
      };

      certificatesResolvers.letsencrypt.acme = {
        storage = "${config.services.traefik.dataDir}/acme.json";
        httpChallenge.entryPoint = "web";
      };
    };

    dynamicConfigOptions.http =
      let
        router = host: extra: {
          rule = "Host(`${host}`)";
          entryPoints = [ "websecure" ];
          tls.certResolver = "letsencrypt";
        } // extra;
      in
      {
        routers = {
          ntfy = router fqdn { service = "ntfy"; };
          status = router statusFqdn {
            service = "gatus";
            middlewares = [ "status-auth" ];
          };
          zone = router zone {
            service = "noop@internal";
            middlewares = [ "to-status" ];
          };
        };
        services = {
          ntfy.loadBalancer.servers = [ { url = "http://${ntfyListen}"; } ];
          gatus.loadBalancer.servers = [ { url = "http://127.0.0.1:${toString gatusPort}"; } ];
        };
        middlewares = {
          status-auth.basicAuth.usersFile = config.sops.templates."traefik-status-users".path;
          to-status.redirectRegex = {
            regex = ".*";
            replacement = "https://${statusFqdn}/";
          };
        };
      };
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  # --- fail2ban: failed logins on notify. / status. --------------------------
  #
  # Traefik's access log (CLF, in the journal) shows every 401: a wrong
  # ntfy password/token or a wrong status page login. 10 within 10 minutes
  # ban the address for http/https only (ssh keeps its own jail), with the
  # same growing ban time as sshd (configuration.nix). WireGuard clients
  # are never banned (ignoreIP there).
  #
  #   fail2ban-client status traefik-auth
  #   fail2ban-client set traefik-auth unbanip <ip>

  services.fail2ban.jails.traefik-auth = {
    filter.Definition = {
      # <client> - <user> [<time>] "<method> <path> <proto>" 401 …
      failregex = ''^<HOST> - \S+ \[[^\]]+\] "[A-Z]+ [^"]*" 401 '';
      journalmatch = "_SYSTEMD_UNIT=traefik.service";
    };
    settings = {
      backend = "systemd";
      port = "http,https";
      maxretry = 10;
      findtime = "10m";
    };
  };

  # --- Gatus: the ping checks from outside ---------------------------------

  services.gatus = {
    enable = true;
    environmentFile = config.sops.templates."gatus.env".path;
    settings = {
      web = {
        address = "127.0.0.1";
        port = gatusPort;
      };
      ui = {
        title = "Homelab status";
        header = "Homelab";
      };
      storage = {
        type = "sqlite";
        path = "/var/lib/gatus/data.db";
      };

      alerting.ntfy = {
        # local, so alerts still go out when Traefik or the certificate breaks
        url = "http://${ntfyListen}";
        inherit topic;
        token = "\${NTFY_TOKEN}";
        priority = 4;
        default-alert = {
          failure-threshold = 3;
          success-threshold = 2;
          send-on-resolved = true;
        };
      };

      endpoints = [
        (https "notify" "ntfy" "https://${fqdn}/v1/health" [ "[BODY].healthy == true" ])
        # the homelab as seen from outside: the WireGuard tunnel, and the
        # monitoring stack behind it (if these fail, Grafana's alerts from
        # inside cannot arrive either)
        (connected "home" "home-openwrt (WireGuard)" "icmp://${homeRouter}")
        (connected "home" "nix-loki" "tcp://${nodes.nix-loki.ip}:${toString nodes.nix-loki.port}")
        (connected "home" "nix-thanos" "tcp://${nodes.nix-thanos.ip}:19291")
      ]
      ++ map (h: https "public" h "https://${h}" [ ]) publicVhosts;
    };
  };
}
