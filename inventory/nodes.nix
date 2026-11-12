# ─────────────────────────────────────────────────────────────────────────────
# Homelab inventory: one entry per LXC node. This is the ONLY place to add one.
#
#   ip        address on the "service" VLAN (10.60.1.0/24)
#   hostname  default public name   -> <hostname>.<baseDomain>
#   sub       alternative public subdomain used by some vhosts (e.g. "sso")
#   port      primary service port (used by nginx / other services)
#   age       the node's age key (ssh-to-age of its ssh host key); it can
#             decrypt services/<service>/*.enc.yaml. See inventory/sops.nix.
#   sopsReaders  other nodes that may also decrypt this service's secrets
#   db        true -> nix-postgres creates database + user "<service>" and
#             syncs its password from services/<service>/postgres.enc.yaml
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
    age = "age1hlrrupj5kcjawrdkujygpsvtwc4y6td0jcah758sply05p92ps9qa6gsaq";
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
    age = "age1lxmq9lg6xdytfld525vmep3j0ndv9m6esrzfjfqx25qgygvjxcdqga48y2";
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
    age = "age135a39l9pweag59mdvzjs34ndmpza2utd7tew2j6s4fpffnqgf54suqltru";
    hostname = "postgres";
    port = 5432;
    dns = null;
    tcp = [ 5432 ];
  };

  # --- Identity Provider ---
  nix-keycloak = {
    ip = "10.60.1.22";
    age = "age1cphj25m2fa320yjy0mtt6l0u9k9v78g0s3x69msgx2gxhjdjz5jsu0ztu6";
    db = true; # database + user on nix-postgres
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
    age = "age1tr07ymeucgt9rp3cwjp9nmef6zss9jlszjaqw66dekr8mrctv94sghrfv7";
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
    age = "age1zer03mv8vrpem0tntknsfudv66nlvttzlvdvq05t7434r2w96dtqx7cpmy";
    db = true; # database + user on nix-postgres
    hostname = "hedgedoc";
    port = 3005;
    tcp = [ 3005 ];
  };

  nix-listmonk = {
    ip = "10.60.1.24";
    age = "age14ne78pjpeqhxaclldk5dhumc208z6gyeepecc6sm3aprmt5q3ssq7xml8l";
    db = true; # database + user on nix-postgres
    hostname = "listmonk";
    sub = "newsletter";
    port = 9000;
    tcp = [ 9000 ];
  };

  nix-paperless = {
    ip = "10.60.1.32";
    age = "age1jau78xmks5656ck6vlv4g3hg9j3gnjh8u2l552q9v2lmxazhm4ts474ayc";
    db = true; # database + user on nix-postgres
    hostname = "paperless";
    port = 28981;
    tcp = [ 28981 ];
  };

  nix-immich = {
    ip = "10.60.1.35";
    age = "age1y9ykrzglk2w9sj546awh4qr0pfhq7xlm8nnq4hvmg8gpqyc6md2qzyjap8";
    db = true; # database + user on nix-postgres
    hostname = "immich";
    sub = "photo";
    port = 2283;
    tcp = [ 2283 ];
  };

  nix-commafeed = {
    ip = "10.60.1.36";
    age = "age10ewzse5566z4uz5dng54mqwr2cnqp579uzt99235nq5qj0ju2vnszqn945";
    db = true; # database + user on nix-postgres
    hostname = "commafeed";
    sub = "rss";
    port = 8082;
    tcp = [ 8082 ];
  };

  nix-sure = {
    ip = "10.60.1.37";
    age = "age13q9z3xle955eumzurctg5huxrq836f2frgp9529mp0v3lz94v3fsw7r7up";
    db = true; # database + user on nix-postgres
    hostname = "sure";
    sub = "sure";
    port = 3000;
    tcp = [ 3000 ];
    deploy.activationTimeout = 600; # db:prepare on first boot is slow
  };

  nix-opencloud = {
    ip = "10.60.1.14";
    age = "age16a49l2a56x7cggxrm435s4lldxsq3ntwclc8z8426kg953xk5pjqpcytwd";
    hostname = "opencloud";
    port = 9200;
    tcp = [ 9100 ];
  };

  nix-tranquil = {
    ip = "10.60.1.39";
    age = "age12s7wtm5k630w7q7znk6g3zz5299gym697clpvtmar56cltudx4qq6lfs4r";
    db = true; # database + user on nix-postgres
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
    age = "age1278lr6sh049xr4t5e9gw6mv5qlnkkmag32cem9ffd2fvf7eu3axq8hdpx6";
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
    age = "age1cxvhh5jqfxgsgyd0ljsdvgn0lyqz6pdshxsl0w7tjlv7wy6ufdcs994vw4";
    hostname = "flathunter";
    # Outbound-only crawler; nothing listens unless the web UI is enabled
    # (then add `tcp = [ 8080 ];` and a `sub`).
    port = 8080;
    deploy = false;
  };

  # --- Smart Home ---
  nix-homeassistant = {
    ip = "10.60.1.33";
    age = "age1jj90rpvwju98ssmp4n2755fa6zmcyql489k8qh6hnnwfg4fmdcyscm4k3h";
    db = true; # database + user on nix-postgres
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
    sopsReaders = [ "nix-influx" ];
    age = "age1sj998jequkhv0qqrx8futqvemy75080guz7zna0v6kz5hvtfxv6qtacary";
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
    age = "age12pdk27hcxvk8fgc7r0rtt8l4tzjaghppgj3suyuz4vuqzlnft43sa6cjsy";
    hostname = "influxv2";
    port = 8086;
    service = "influxv2";
    sopsReaders = [ "nix-grafana" ];
    tcp = [ 8086 ];
    deploy = false;
  };

  # --- Infra ---
  nix-build = {
    ip = "10.60.1.15";
    age = "age1wnyjcxf6jjc60tdgaf4eaf3hcmpkvx25mjtc6tmhy8j9689tp9lq7nw262";
    hostname = "build";
    port = 0;
    deploy = false;
  };
}
