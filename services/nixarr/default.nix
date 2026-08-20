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

  beetsWithPlugins = pkgs.python3Packages.beets.override {
    pluginOverrides = {
      chroma.enable = true; # AcoustID - not on by default
    };
  };

  # --------------------------------------------------------------------------
  # Beets matching policy
  #
  # Kept in its own file and pulled in via `include:` so it can be shared by the
  # tag / manual configs without multi-line Nix string interpolation.
  #
  # max_rec is the important half. Without it a single penalty (e.g. `year`)
  # caps the recommendation at "medium" no matter how good the overall score is,
  # and quiet mode then skips the release - which is why 99.8% matches were
  # being dropped. The zeroed distance weights stop WEB rips being penalised
  # against digital reissues carrying a different year/country/label.
  # --------------------------------------------------------------------------
  beetsMatchConfig = pkgs.writeText "beets-match.yaml" ''
    match:
      strong_rec_thresh: 0.12
      medium_rec_thresh: 0.30
      rec_gap_thresh: 0.25
      max_rec:
        missing_tracks: medium
        unmatched_tracks: medium
        track_title: strong
        artist: strong
        album: strong
        media: strong
        mediums: strong
        year: strong
        country: strong
        label: strong
        catalognum: strong
      distance_weights:
        country: 0.0
        year: 0.0
        media: 0.0
        label: 0.0
        catalognum: 0.0
      preferred:
        countries: []
        media: []
      ignored_media: []
  '';

  # --------------------------------------------------------------------------
  # Stage 1: identify and write MusicBrainz IDs into the files.
  #
  # Runs BEFORE Lidarr sees the release, as a SABnzbd post-processing script.
  # Fast: no artwork, no lyrics, no replaygain. The only job here is to get
  # MUSICBRAINZ_ALBUMID / MUSICBRAINZ_RELEASETRACKID into the tags so Lidarr's
  # matcher (release-ID weight 5.0, recording-ID weight 10.0) can do its job.
  # --------------------------------------------------------------------------
  beetsTagConfig = pkgs.writeText "beets-tag.yaml" ''
    include:
      - ${beetsMatchConfig}
    directory: /data/media/library/music
    import:
      move: no          # critical - do not reorganise, Lidarr owns placement
      copy: no          # critical - same reason
      write: yes
      quiet: yes
      quiet_fallback: skip
      timid: no
      autotag: yes
      duplicate_action: keep
    plugins: chroma fromfilename musicbrainz
    chroma:
      auto: yes
  '';

  # --------------------------------------------------------------------------
  # Stage 2: enrichment. Runs AFTER Lidarr has imported, on Lidarr's copy.
  #
  # Artwork / lyrics / replaygain are slow and network-bound, so they are kept
  # out of the download path where they would stall the SAB queue. -A on the
  # command line skips re-matching, since stage 1 already tagged these files.
  # --------------------------------------------------------------------------
  beetsEnrichConfig = pkgs.writeText "beets-enrich.yaml" ''
    directory: /data/media/library/music
    import:
      move: no
      copy: no
      write: yes
      quiet: yes
      timid: no
      duplicate_action: keep
    plugins: fetchart embedart lyrics replaygain musicbrainz
    fetchart:
      auto: yes
      maxwidth: 1200
      sources: filesystem coverart itunes
    embedart:
      auto: yes
      maxwidth: 1200
    replaygain:
      auto: yes
      backend: ffmpeg
    lyrics:
      auto: yes
  '';

  # --------------------------------------------------------------------------
  # Interactive config, for the second pass over whatever stage 1 still skips.
  #   beet -c /etc/beets/manual.yaml -l /tmp/manual.db import -t <dir>
  # --------------------------------------------------------------------------
  beetsManualConfig = pkgs.writeText "beets-manual.yaml" ''
    include:
      - ${beetsMatchConfig}
    directory: /data/media/library/music
    import:
      move: no
      copy: no
      write: yes
      quiet: no
      timid: yes
      autotag: yes
      duplicate_action: keep
    plugins: chroma fromfilename musicbrainz
    chroma:
      auto: yes
  '';

  # --------------------------------------------------------------------------
  # Pre-import hook. Invoked by SABnzbd with the completed job directory as $1.
  #
  # The library DB is a throwaway in a tempdir on purpose: a persistent DB makes
  # beets refuse re-runs with "This album is already in the library! Skipping."
  # A tag-only pass has no use for library state.
  #
  # Always exits 0 - SABnzbd marks a job failed on a non-zero script exit, and a
  # beets hiccup should not fail the download.
  # --------------------------------------------------------------------------
  beetsPreImport = pkgs.writeShellApplication {
    name = "beets-pre-import";
    runtimeInputs = [
      beetsWithPlugins
      pkgs.chromaprint # fpcalc, for chroma
      pkgs.coreutils
    ];
    text = ''
      target="''${1:-}"
      [ -d "$target" ] || exit 0

      workdir="$(mktemp -d)"
      trap 'rm -rf "$workdir"' EXIT
      export HOME="$workdir"
      export XDG_CONFIG_HOME="$workdir/.config"

      beet --config ${beetsTagConfig} \
           --library "$workdir/library.db" \
           import --quiet "$target" || true

      exit 0
    '';
  };

  # --------------------------------------------------------------------------
  # Post-import hook. Wired into Lidarr as a Custom Script on Download Import.
  # Lidarr_AddedTrackPaths is only populated once an import has SUCCEEDED, so
  # this can only ever do enrichment - it cannot fix a failed match.
  # --------------------------------------------------------------------------
  beetsImport = pkgs.writeShellApplication {
    name = "lidarr-beets-import";
    runtimeInputs = [
      beetsWithPlugins
      pkgs.chromaprint
      pkgs.ffmpeg # replaygain backend
      pkgs.imagemagick # embedart resizing
      pkgs.coreutils
      pkgs.findutils
    ];
    text = ''
      [ -n "''${Lidarr_AddedTrackPaths:-}" ] || exit 0

      workdir="$(mktemp -d)"
      trap 'rm -rf "$workdir"' EXIT
      export HOME="$workdir"
      export XDG_CONFIG_HOME="$workdir/.config"

      printf '%s' "$Lidarr_AddedTrackPaths" | tr '|' '\n' \
        | xargs -r -n1 dirname | sort -u \
        | while read -r dir; do
            beet --config ${beetsEnrichConfig} \
                 --library "$workdir/library.db" \
                 import --quiet --noautotag "$dir" || true
          done

      exit 0
    '';
  };
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
        scaling_factor = 2; # Lower from 5 to 2 to heavily reduce write rate
        save_files_threshold = 10; # Lower from 100 to stop saving giant file lists inside torrents
        save_pieces = false;
      };
    };
  };

  systemd.services.pg-vacuum = {
    script = "${pkgs.postgresql}/bin/psql -d bitmagnet -c 'VACUUM FULL ANALYZE;'";
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

  environment.systemPackages = [
    beetsWithPlugins
    pkgs.chromaprint
    pkgs.ffmpeg
    pkgs.imagemagick
  ];

  # Interactive config for cleaning up leftovers by hand.
  environment.etc."beets/manual.yaml".source = beetsManualConfig;

  # Stable paths for the hooks - the store path changes on every rebuild,
  # these don't.
  environment.etc."beets/lidarr-import.sh".source = "${beetsImport}/bin/lidarr-beets-import";

  # SABnzbd post-processing script. Point SAB at this directory under
  # Config -> Folders -> Post-Processing Scripts Folder, then set
  # Script = beets-tag.sh on the music category.
  environment.etc."sabnzbd/scripts/beets-tag.sh" = {
    source = "${beetsPreImport}/bin/beets-pre-import";
    mode = "0755";
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
    secrets.aurral_oidc_client_secret = {
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

      "seerr.env".content = ''
        OIDC_CLIENT_SECRET=${config.sops.placeholder.oidc_client_secret}
      '';
      "aurral.env".content = ''
        OIDC_CLIENT_SECRET=${config.sops.placeholder.aurral_oidc_client_secret}
      '';
    };
  };

  # 3. Virtualization & OCI Containers Layer
  virtualisation.docker.enable = true;
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      #   seerr = {
      #     image = "ghcr.io/seerr-team/seerr:0078a48";
      #     autoStart = true;
      #     ports = [
      #       "5055:5055"
      #     ];
      #     environment = {
      #       PUID = "1000";
      #       PGID = "1000";
      #       TZ = "Etc/UTC";
      #       PORT = "5055";
      #       OIDC_ISSUER_URL = "${keycloakUrl}/realms/${keycloakRealm}";
      #       OIDC_CLIENT_ID = "seerr";
      #       OIDC_REDIRECT_URI = "https://seerr.${baseDomain}/api/v1/auth/oidc/callback";
      #     };
      #     environmentFiles = [
      #       config.sops.templates."seerr.env".path
      #     ];
      #     volumes = [
      #       "/data/media/.state/nixarr/seerr:/app/config"
      #     ];
      #     extraOptions = [
      #       "--user=1000:1000"
      #       "--network=host"

      #     ];

      #   };

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
        image = "ghcr.io/habirabbu/droppedneedle:latest";
        autoStart = false;
        environment = {
          PUID = "1000";
          PGID = "1000";
          PORT = "8688";
          TZ = "Etc/UTC";
        };
        volumes = [
          "/var/lib/musicseerr/config:/app/config"
          "/var/lib/musicseerr/cache:/app/cache"
          "/data/media/library/music:/data/media/library/music:ro"
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
        image = "ghcr.io/lklynet/aurral:2.4.0";
        autoStart = true;
        environment = {
          PUID = "1000";
          PGID = "1000";
          TZ = "Etc/UTC";
          DOWNLOAD_FOLDER = "/data/media/downloads/aurral";
          OIDC_ENABLED = "true";
          OIDC_ISSUER = "${keycloakUrl}/realms/${keycloakRealm}"; # e.g. https://auth.yourdomain.com/realms/your-realm
          OIDC_CLIENT_ID = "aurral";
          OIDC_REDIRECT_URI = "https://aurral.${baseDomain}/sso/callback";
          OIDC_GROUPS_CLAIM = "groups";
          # Optional mapping configurations:
          OIDC_SCOPES = "openid profile email";
          OIDC_USERNAME_CLAIM = "preferred_username";
          OIDC_DEFAULT_ROLE = "user"; # "user" or "admin"
          # OIDC_ADMIN_USERS = "your-admin-username";
          OIDC_ADMIN_GROUPS = "aurral_admin";
          OIDC_LOGOUT_URL = "${keycloakUrl}/realms/${keycloakRealm}/protocol/openid-connect/logout";
        };
        environmentFiles = [
          config.sops.templates."aurral.env".path
        ];
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
