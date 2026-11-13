# ─────────────────────────────────────────────────────────────────────────────
# Homelab inventory: one entry per container on the homelab host
# (hosts/homelab). This is the ONLY place to add one.
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
#             null = inventory-only node, no container is built)
#   autoStart false -> the container is built but not started at boot
#             (default: true). Start by hand: systemctl start container@<name>
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
    age = "age1hf2xhlpp4xjnjsu868uqhzwg9r5d2cy223ytwq4jue63kenvk9mqy2vefj";
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
    age = "age18q08xugmqphq4f5avdpygt2tk9uhyuq4l4f0xz8we3z7e7mwvc6qv77cp0";
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
    age = "age1ktjfgv8xrxpy8ejyvg82085had5cn59vge0h5r8d4j29p6tjjghsh7jvnv";
    hostname = "postgres";
    port = 5432;
    dns = null;
    tcp = [ 5432 ];
  };

  # --- Identity Provider ---
  nix-keycloak = {
    ip = "10.60.1.22";
    age = "age1lsvmk9n7pz59hugwhena6azczntfk4stet03v582lrukraukkqes54h3c4";
    db = true; # database + user on nix-postgres
    hostname = "keycloak";
    sub = "sso";
    port = 8080;
    tcp = [ 8080 ];
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
    age = "age18fc6sktrdeuh0zdkg8wamp4n2gasynjmyzmxehtw8mdmyhr8xy5s6z3j5h";
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
    age = "age15a7p5ltx5kv94ftkepwffwyungaryv3ny55c5fs5ukmx95jmfvesezfr5u";
    db = true; # database + user on nix-postgres
    hostname = "hedgedoc";
    port = 3005;
    tcp = [ 3005 ];
  };

  nix-listmonk = {
    ip = "10.60.1.24";
    age = "age104skts33cen67tkcpryutzppxpzmg6jy4xr4zuk7fh3vrsf4zdwq2k5q3n";
    db = true; # database + user on nix-postgres
    hostname = "listmonk";
    sub = "newsletter";
    port = 9000;
    tcp = [ 9000 ];
  };

  nix-paperless = {
    ip = "10.60.1.32";
    age = "age1zuvatjt9fl08tuye2e5vz2j2q9yt59607rza00dleygr559294gqavxert";
    db = true; # database + user on nix-postgres
    hostname = "paperless";
    port = 28981;
    tcp = [ 28981 ];
  };

  nix-immich = {
    ip = "10.60.1.35";
    age = "age19htsz09n6jkpvl58nwqkuqq6yutckg8jnq7nfcv6wqtsz2eeuvfsvs6gjr";
    db = true; # database + user on nix-postgres
    hostname = "immich";
    sub = "photo";
    port = 2283;
    tcp = [ 2283 ];
  };

  nix-commafeed = {
    ip = "10.60.1.36";
    age = "age1au0mwv5j852amftsellzfyuc26xtceuy4w2jzswxh77fzlkfku4spgx2eq";
    db = true; # database + user on nix-postgres
    hostname = "commafeed";
    sub = "rss";
    port = 8082;
    tcp = [ 8082 ];
  };

  nix-sure = {
    ip = "10.60.1.37";
    age = "age1qx8eum7sdfv8935tps0dnhysq3h7q3fjqep9usr6clpyajpc8gyqqmq404";
    db = true; # database + user on nix-postgres
    hostname = "sure";
    sub = "sure";
    port = 3000;
    tcp = [ 3000 ];
  };

  nix-opencloud = {
    ip = "10.60.1.14";
    age = "age1va00gwuz7fkjpctd6zvx45t87e8cg86r5xs0gae2022nzx93fv2sr35df6";
    hostname = "opencloud";
    port = 9200;
    tcp = [ 9100 ];
  };

  nix-tranquil = {
    ip = "10.60.1.39";
    age = "age1xs3c6d6kujddr8s2qxkk22z50fu8gevt2qhf4zyljrl73tx52y0s069ptc";
    db = true; # database + user on nix-postgres
    hostname = "tranquil";
    sub = "pds"; # -> pds.hackler.io, handles at <name>.pds.hackler.io
    port = 3000;
    tcp = [ 3000 ];
    autoStart = false; # CT was stopped on pve2
  };

  nix-arr = {
    ip = "10.60.1.31";
    age = "age1qszselhewckzku7657c48upl77xexwj2j4eascwlk9ju8sstpq7s5znpvw";
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
    age = "age1d03hq7wn8lzl8trhdf83d4c6zkynrdkuxee5ct8xd5gm4jcx9yfs2r03vc";
    hostname = "flathunter";
    # Outbound-only crawler; nothing listens unless the web UI is enabled
    # (then add `tcp = [ 8080 ];` and a `sub`).
    port = 8080;
    autoStart = false; # CT was stopped on pve2
  };

  # --- Smart Home ---
  nix-homeassistant = {
    ip = "10.60.1.33";
    age = "age1wj67p0vyn4tractla52dzq8spjz4gn34j20e94ds4zg24vxcea8qnu0vpa";
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
  };

  nix-grafana = {
    ip = "10.60.1.25";
    sopsReaders = [ "nix-influx" ];
    age = "age1knduw4awu7sycxvv7dcajldcwts7ppxgctasvecuw2xfx33fccasqrmut4";
    hostname = "grafana";
    port = 3000;
    tcp = [
      3000
      3100
    ];
  };

  nix-influx = {
    ip = "10.60.1.26";
    age = "age1u437e92k3dg0dlkex8sr856yrtz4yqt0w66ey0xu5qk0e4gxxgqqlq9fdd";
    hostname = "influxv2";
    port = 8086;
    service = "influxv2";
    sopsReaders = [ "nix-grafana" ];
    tcp = [ 8086 ];
    autoStart = false; # had no CT on pve2: starts empty, enable when ready
  };

  # --- Infra ---
  # Retired: the homelab host builds for itself now (services/build is
  # imported by hosts/homelab). Kept so its IP stays reserved.
  nix-build = {
    ip = "10.60.1.15";
    age = "age1wnyjcxf6jjc60tdgaf4eaf3hcmpkvx25mjtc6tmhy8j9689tp9lq7nw262";
    hostname = "build";
    port = 0;
    service = null;
  };
}
