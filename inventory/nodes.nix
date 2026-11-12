# ─────────────────────────────────────────────────────────────────────────────
# Homelab inventory: one entry per LXC node. This is the ONLY place to add one.
#
#   ip        address on the "service" VLAN (10.60.1.0/24)
#   hostname  default public name   -> <hostname>.<baseDomain>
#   sub       alternative public subdomain used by some vhosts (e.g. "sso")
#   port      primary service port (used by nginx / other services)
#   tcp, udp  firewall ports to open (default: none)
#
#   service   directory under ./services   (default: name without "nix-";
#             null = inventory-only node, no nixosConfiguration is built)
#   deploy    deploy-rs overrides attrset, or false to skip deploy-rs
#             (default: {} = deployed with defaults)
#
#   gateway   false  -> no default gateway   (default: service VLAN gateway)
#   dns       list of nameservers, or null to leave unset (default: adguard)
#   extraNetworking  merged (recursively) into the generated `networking`
#
# See ./default.nix for how these turn into `nodes.<name>.networking`.
# ─────────────────────────────────────────────────────────────────────────────
{
  # --- Edge Proxy ---
  nix-nginx = {
    ip = "10.60.1.17";
    hostname = "nginx";
    port = 443;
    tcp = [
      80
      443
    ];
    gateway = false; # default route goes out via the DMZ instead
    dns = [
      "1.1.1.1"
      "9.9.9.9"
    ];
    extraNetworking = {
      interfaces.service.ipv4.routes = [
        {
          address = "10.60.0.0";
          prefixLength = 24;
          via = "10.60.1.1";
        }
        {
          address = "100.64.0.0";
          prefixLength = 24;
          via = "10.60.1.1";
        }
      ];
      interfaces.dmz.ipv4.addresses = [
        {
          address = "10.60.50.17";
          prefixLength = 24;
        }
      ];
      defaultGateway.address = "10.60.50.1";
      defaultGateway.interface = "dmz";
    };
  };

  # --- DNS & Ad-Blocking ---
  nix-adguard = {
    ip = "10.60.1.16";
    hostname = "adguard";
    port = 3000;
    service = "adguardhome";
    dns = null;
    tcp = [
      53
      80
      443
      3000
    ];
    udp = [ 53 ];
  };

  # --- Database (Postgres) ---
  nix-postgres = {
    ip = "10.60.1.20";
    hostname = "postgres";
    port = 5432;
    dns = null;
    tcp = [ 5432 ];
  };

  # --- Identity Provider ---
  nix-keycloak = {
    ip = "10.60.1.22";
    hostname = "keycloak";
    sub = "sso";
    port = 8080;
    tcp = [ 8080 ];
    deploy.activationTimeout = 600;
  };

  # Retired; kept so its IP stays reserved.
  nix-zitadel = {
    ip = "10.60.1.21";
    hostname = "zitadel";
    port = 8081;
    service = null;
    tcp = [ 8081 ];
  };

  # --- VPN & Mesh (Headscale) ---
  nix-headscale = {
    ip = "10.60.1.30";
    hostname = "headscale";
    port = 8080;
    tcp = [
      8080
      3000
      9090
    ];
    udp = [ 3478 ];
  };

  # --- Apps ---
  nix-hedgedoc = {
    ip = "10.60.1.23";
    hostname = "hedgedoc";
    port = 3005;
    tcp = [ 3005 ];
  };

  nix-listmonk = {
    ip = "10.60.1.24";
    hostname = "listmonk";
    sub = "newsletter";
    port = 9000;
    tcp = [ 9000 ];
  };

  nix-paperless = {
    ip = "10.60.1.32";
    hostname = "paperless";
    port = 28981;
    tcp = [ 28981 ];
  };

  nix-immich = {
    ip = "10.60.1.35";
    hostname = "immich";
    sub = "photo";
    port = 2283;
    tcp = [ 2283 ];
  };

  nix-commafeed = {
    ip = "10.60.1.36";
    hostname = "commafeed";
    sub = "rss";
    port = 8082;
    tcp = [ 8082 ];
  };

  nix-sure = {
    ip = "10.60.1.37";
    hostname = "sure";
    sub = "sure";
    port = 3000;
    tcp = [ 3000 ];
    deploy.activationTimeout = 600; # db:prepare on first boot is slow
  };

  nix-opencloud = {
    ip = "10.60.1.14";
    hostname = "opencloud";
    port = 9200;
    tcp = [ 9100 ];
  };

  nix-tranquil = {
    ip = "10.60.1.39";
    hostname = "tranquil";
    sub = "pds"; # -> pds.hackler.io, handles at <name>.pds.hackler.io
    port = 3000;
    tcp = [ 3000 ];
    deploy = false;
  };

  nix-sparkyfitness = {
    ip = "10.60.1.38";
    hostname = "sparkyfitness";
    sub = "fitness";
    port = 80;
    # The module's own nginx serves the frontend + API on :80; nix-nginx
    # terminates TLS and forwards here.
    tcp = [ 80 ];
    # Not built yet: services/sparkyfitness needs an `inputs.sparkyfitness`
    # flake input that does not exist.
    service = null;
  };

  nix-arr = {
    ip = "10.60.1.31";
    hostname = "nixarr";
    # Nixarr has no single port; Jellyfin is the primary UI.
    port = 8096;
    service = "nixarr";
    tcp = [
      8096 # Jellyfin
      8989 # Sonarr
      7878 # Radarr
      8686
      3333
      5055
      6767
      6060
      8688
      8084 # Shelfmark
      8787
      9696 # Prowlarr
      9091 # Transmission/RPC
    ];
    udp = [
      51820 # WireGuard (Nixarr VPN)
    ];
  };

  nix-flathunter = {
    ip = "10.60.1.40";
    hostname = "flathunter";
    # Outbound-only crawler; nothing listens unless the web UI is enabled
    # (then add `tcp = [ 8080 ];` and a `sub`).
    port = 8080;
    deploy = false;
  };

  # --- Smart Home ---
  nix-homeassistant = {
    ip = "10.60.1.33";
    hostname = "homeassistant";
    port = 8123;
    service = "hass";
    tcp = [
      1883
      5000
      8123
      8082
      8096
      8095
      8097
      8081
    ];
    udp = [
      1900
      5353
      5540
    ];
    extraNetworking = {
      hosts = {
        "10.60.1.33" = [
          "nix-homeassistant"
          "nix-homeassistant.local"
        ];
        "fd00:60:1::33" = [
          "nix-homeassistant"
          "nix-homeassistant.local"
        ];
      };
      interfaces.iot.ipv4.addresses = [
        {
          address = "10.60.60.33";
          prefixLength = 24;
        }
      ];
      interfaces.service.ipv6.addresses = [
        {
          address = "fd00:60:1::33";
          prefixLength = 64;
        }
      ];
      interfaces.service.ipv6.routes = [
        {
          address = "::";
          prefixLength = 0;
          via = "fd00:60:1::1";
        }
      ];
      interfaces.wireguard.ipv4.addresses = [
        {
          address = "10.60.99.33";
          prefixLength = 24;
        }
      ];
      firewall.allowedUDPPortRanges = [
        {
          from = 6001;
          to = 6010;
        }
      ];
    };
  };

  nix-unifi-controller = {
    ip = "10.60.1.34";
    hostname = "unifi";
    port = 8443;
    dns = null;
    tcp = [
      8080 # Device Inform (crucial!)
      8443 # Management UI
    ];
    udp = [
      3478 # STUN
      10001 # Discovery
      19002
    ];
    extraNetworking.hosts = {
      "127.0.0.1" = [
        "localhost"
        "nix-unifi-controller"
      ];
      "::1" = [
        "localhost"
        "nix-unifi-controller"
      ];
    };
  };

  # --- Observability ---
  nix-loki = {
    ip = "10.60.1.27";
    hostname = "loki";
    port = 3100;
    gateway = false;
    dns = null;
    tcp = [
      3100 # Loki HTTP (Alloy ingestion & Grafana queries)
      9096 # Loki gRPC
      12345
    ];
    deploy = false;
  };

  nix-grafana = {
    ip = "10.60.1.25";
    hostname = "grafana";
    port = 3000;
    tcp = [
      3000
      3100
    ];
    deploy = false;
  };

  nix-influx = {
    ip = "10.60.1.26";
    hostname = "influxv2";
    port = 8086;
    service = "influxv2";
    tcp = [ 8086 ];
    deploy = false;
  };

  # --- Infra ---
  nix-build = {
    ip = "10.60.1.15";
    hostname = "build";
    port = 0;
    deploy = false;
  };
}
