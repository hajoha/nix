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
  };

  # 3. Virtualization & OCI Containers Layer
  virtualisation.docker.enable = true;
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      musicseerr = {
        image = "ghcr.io/habirabbu/musicseerr:v1.4.2";
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
