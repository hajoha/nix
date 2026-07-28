{
  config,
  lib,
  pkgs,
  nodes,
  baseDomain,
  keycloakRealm,
  ...
}:

let
  keycloakUrl = "https://${nodes.nix-keycloak.sub}.${baseDomain}";
  stateDir = "/data/media/.state/nixarr/seerr";
in
{
  # 1. Core Nixarr Configuration
  services.flaresolverr = {
    enable = true;
    port = 8191;
    openFirewall = false;
  };
  nixpkgs.config.allowUnfree = true;
  nixarr = {
    enable = true;
    mediaDir = "/data/media";
    stateDir = "/data/media/.state/nixarr";

    vpn = {
      enable = true;
      wgConf = "/data/.secret/wg.conf";
    };

    jellyfin.enable = true;
    transmission = {
      enable = true;
      vpn.enable = true;
      peerPort = 51820;
    };

    bazarr.enable = true;
    lidarr.enable = true;
    prowlarr.enable = true;
    radarr.enable = true;
    sonarr.enable = true;
    seerr.enable = true;
    sabnzbd.enable = true;
    sabnzbd.openFirewall = true;
    shelfmark.enable = true;
    shelfmark.openFirewall = true;
    shelfmark.host = "0.0.0.0";

  };
  systemd.services.shelfmark.environment = {
    HIDE_LOCAL_AUTH = "false";
    DISABLE_LOCAL_AUTH = "false";
    OIDC_AUTO_REDIRECT = "false";
  };

  systemd.services.bitmagnet.vpnconfinement = {
    enable = true;
    vpnnamespace = "wg";
  };

  systemd.services.bitmagnet.serviceConfig = {
    DynamicUser = lib.mkForce false;
    RestrictNamespaces = lib.mkForce false;
    PrivateMounts = lib.mkForce false;
    RestrictAddressFamilies = lib.mkForce [
      "AF_UNIX"
      "AF_INET"
      "AF_INET6"
      "AF_NETLINK"
    ];
  };

  vpnNamespaces.wg = {
    openVPNPorts = [ ];
    portMappings = [
      {
        from = 3333;
        to = 3333;
      }
    ];
  };

  services.bitmagnet = {
    enable = true;
    openFirewall = false;
    useLocalPostgresDB = true;
    user = "bitmagnet";
    group = "bitmagnet";
    settings = {
      http_server.port = "0.0.0.0:3333";
      dht_server.port = 3334;
      postgres = {
        host = "/run/postgresql";
        name = "bitmagnet";
        user = "bitmagnet";
      };
      dht_crawler = {
        scaling_factor = 5; # Reduce from default 10 to lower CPU/Disk load
        save_files_threshold = 100; # Prevent giant torrents from bloating the DB
        save_pieces = false; # Ensure this is false
      };
    };
  };

  systemd.services.pg-vacuum = {
    script = "${pkgs.postgresql}/bin/psql -d bitmagnet -c 'VACUUM ANALYZE;'";
    serviceConfig.User = "postgres";
  };
  systemd.timers.pg-vacuum = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "weekly";
  };
  systemd.tmpfiles.rules = [
    "d /data/media/.state/grimmory 0755 root root -"
    "d /data/media/.state/grimmory/data 0755 1000 169 -"
    "d /data/media/.state/grimmory/mariadb 0755 root root -"
    "d /data/media/.state/bindery 0755 root root -"
    "d /data/media/.state/bindery/config 0755 1000 1000 -"
    "d /data/media/downloads/bookdrop 0775 1000 169 -"
    "d /data/media/downloads/books 0775 1000 169 -"
    "d /data/media/downloads/audiobooks 0775 1000 169 -"
  ];
  services.postgresql = {
    enable = true;
    # Increase autovacuum frequency for the bitmagnet database
    settings = {
      autovacuum = "on";
      autovacuum_vacuum_scale_factor = "0.05"; # Vacuum more often (at 5% bloat)
      autovacuum_analyze_scale_factor = "0.02";
    };
  };

  # 2. SOPS Configuration Matrix
  sops = {
    defaultSopsFile = ./secrets.enc.yaml;
    validateSopsFiles = false;
    secrets.oidc_client_secret = {
      owner = "root";
    };
    # NEW: add grimmory_db_password to secrets.enc.yaml
    secrets.grimmory_db_password = { };
    templates = {
      # Env file consumed by the grimmory app container
      "grimmory.env".content = ''
        DATABASE_PASSWORD=${config.sops.placeholder.grimmory_db_password}
      '';
      # Env file consumed by the mariadb container
      "grimmory-db.env".content = ''
        MYSQL_PASSWORD=${config.sops.placeholder.grimmory_db_password}
        MYSQL_ROOT_PASSWORD=${config.sops.placeholder.grimmory_db_password}
      '';
    };
  };

  # 3. Virtualization & OCI Containers Layer
  virtualisation.docker.enable = true;
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {

      # --- Books: library / reading layer (replaces autocaliweb) ---
      grimmory-mariadb = {
        image = "lscr.io/linuxserver/mariadb:latest";
        autoStart = true;
        environment = {
          PUID = "1000";
          PGID = "1000";
          TZ = "Etc/UTC";
          MYSQL_DATABASE = "grimmory";
          MYSQL_USER = "grimmory";
        };
        environmentFiles = [
          config.sops.templates."grimmory-db.env".path
        ];
        volumes = [
          "/data/media/.state/grimmory/mariadb:/config"
        ];
      };

      grimmory = {
        image = "ghcr.io/grimmory-tools/grimmory:latest";
        autoStart = true;
        ports = [
          "6060:6060" # Web UI / OPDS / KOReader & Kobo sync
        ];
        environment = {
          USER_ID = "1000";
          GROUP_ID = "169"; # see permissions note below
          TZ = "Etc/UTC";
          DATABASE_URL = "jdbc:mariadb://grimmory-mariadb:3306/grimmory";
          DATABASE_USERNAME = "grimmory"; # was DB_USER
        };
        environmentFiles = [
          config.sops.templates."grimmory.env".path
        ];
        volumes = [
          "/data/media/.state/grimmory/data:/app/data"
          "/data/media/library/books:/books"
          "/data/media/downloads/bookdrop:/bookdrop"
        ];
        dependsOn = [ "grimmory-mariadb" ];
        extraOptions = [
          "--link=grimmory-mariadb:grimmory-mariadb"
        ];
      };

      # # --- Books: acquisition layer (replaces shelfmark) ---
      # bindery = {
      #   image = "ghcr.io/vavallee/bindery:latest";
      #   autoStart = true;
      #   ports = [
      #     "8787:8787"
      #   ];
      #   environment = {
      #     BINDERY_PUID = "1000";
      #     BINDERY_PGID = "1000";
      #     TZ = "Etc/UTC";

      #     # --- Reverse proxy (nginx on your proxy host) ---
      #     # IP of the nginx machine as Bindery sees it. Required once you
      #     # switch auth to OIDC/proxy mode; also fixes the per-IP login
      #     # rate-limiter so it bans real clients, not your proxy.
      #     BINDERY_TRUSTED_PROXY = "${nodes.nix-nginx.ip}";
      #     BINDERY_OIDC_REDIRECT_BASE_URL = "https://bindery.${baseDomain}";
      #     # commonProxy forwards X-Forwarded-Proto, so "auto" would work,
      #     # but "always" is the safer explicit choice since all access is TLS.
      #     BINDERY_COOKIE_SECURE = "always";
      #     # BINDERY_URL_BASE = "https://bindery.${baseDomain}";
      #     # --- Local services on the same host (network_mode: host) ---
      #     # Prowlarr hands out download links; if it's configured in Bindery
      #     # as localhost:9696 those links resolve to loopback and get blocked
      #     # by the SSRF guard without this.
      #     BINDERY_DOWNLOAD_ALLOW_LOOPBACK = "1";
      #     BINDERY_AUDIOBOOK_DIR = "/audiobooks";

      #   };
      #   volumes = [
      #     "/data/media/.state/bindery/config:/config"
      #     "/data/media/library/books:/books"
      #     "/data/media/library/audiobooks:/audiobooks"
      #     "/data/media/downloads/books:/downloads"
      #   ];
      #   extraOptions = [
      #     "--network=host"
      #     "--user=1000:1000"
      #     "--group-add=169" # media group: grants write on /books (root:media 775)
      #   ];
      # };

      musicseerr = {
        image = "ghcr.io/habirabbu/musicseerr:v2.3.0";
        autoStart = true;
        environment = {
          PUID = "1000";
          PGID = "1000";
          PORT = "8688";
          TZ = "Etc/UTC";
        };
        volumes = [
          "/var/lib/musicseerr/config:/app/config"
          "/var/lib/musicseerr/cache:/app/cache"
        ];
        extraOptions = [
          "--network=host"
          "--pull=always"
        ];
      };
      profilarr = {
        image = "ghcr.io/dictionarry-hub/profilarr:latest";
        autoStart = true;
        ports = [
          "6868:6868"
        ];
        volumes = [
          "/var/lib/profilarr/config:/config"
        ];
        environment = {
          PUID = "1000";
          PGID = "1000";
          TZ = "Etc/UTC";
          PARSER_HOST = "profilarr-parser"; # Matches the container name/link below
          PARSER_PORT = "5000";
          ORIGIN = "https://profilarr.${baseDomain}";
        };
        # Forces this container to link to the parser container for inter-service communication
        extraOptions = [
          "--link=profilarr-parser:profilarr-parser"
        ];
      };

      # NEW: profilarr-parser container
      profilarr-parser = {
        image = "ghcr.io/dictionarry-hub/profilarr-parser:latest";
        autoStart = true;
        # Docker Compose 'expose' just opens the port to other containers,
        # so we pass it inside the Docker bridge network via extraOptions.
        extraOptions = [
          "--expose=5000"
        ];
      };
      aurral = {
        image = "ghcr.io/lklynet/aurral:latest";
        autoStart = true;
        environment = {
          PUID = "1000";
          PGID = "1000";
          TZ = "Etc/UTC";
          DOWNLOAD_FOLDER = "/data/media/downloads/aurral";
        };
        volumes = [
          # Storage data path for state & internal database
          "/var/lib/aurral/data:/app/backend/data"
          # Where dynamically generated flows/playlists will drop
          "/data/media/downloads/aurral:/app/downloads"
          # Optional RO access to your music library to enable the 'Hardlink' file reuse worker feature
          "/data/media:/data:ro"
        ];
        ports = [
          "3001:3001"
        ];
      };

    };
  };

}
