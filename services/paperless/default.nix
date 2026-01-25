{
  config,
  pkgs,
  lib,
  nodes,
  baseDomain,
  ...
}:

{
  # 1. SOPS Configuration
  sops.defaultSopsFile = ./secrets.enc.yaml;
  sops.secrets = {
    "paperless-creds/env" = {
      owner = "paperless";
    };
    "paperless-creds/oidcSecret" = {
      owner = "paperless";
    };
  };

  services.paperless = {
    enable = true;
    address = "0.0.0.0";
    port = nodes.nixpaperless.port;
    consumptionDirIsPublic = true;

    # Environment file for DB_PASS and other standard secrets
    environmentFile = config.sops.secrets."paperless-creds/env".path;

    settings = {
      PAPERLESS_URL = "https://${nodes.nixpaperless.hostname}";

      # Database connection to central Postgres
      PAPERLESS_DBHOST = nodes.nixpostgres.ip;
      PAPERLESS_DBPORT = toString nodes.nixpostgres.port;
      PAPERLESS_DBUSER = "paperless"; # Ensure this user exists in Postgres

      # Tika & Gotenberg (Running locally in this same container)
      PAPERLESS_TIKA_ENABLED = "1";
      PAPERLESS_TIKA_GOTENBERG_ENDPOINT = "http://localhost:${toString config.services.gotenberg.port}";
      PAPERLESS_TIKA_ENDPOINT = "http://127.0.0.1:${toString config.services.tika.port}";

      # Document Processing
      PAPERLESS_OCR_LANGUAGE = "deu+eng";
      PAPERLESS_CONSUMER_IGNORE_PATTERN = [
        ".DS_STORE/*"
        "desktop.ini"
      ];
      PAPERLESS_OCR_USER_ARGS = {
        optimize = 1;
        pdfa_image_compression = "lossless";
      };

      # SSO / Zitadel Logic
      PAPERLESS_DISABLE_REGULAR_LOGIN = "True";
      PAPERLESS_REDIRECT_LOGIN_TO_SSO = "True";
      PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
      PAPERLESS_SOCIALACCOUNT_PROVIDERS = builtins.toJSON {
        openid_connect = {
          OAUTH_PKCE_ENABLED = "True";
          APPS = [
            {
              provider_id = "zitadel";
              name = "Zitadel";
              client_id = "351648507242807573";
              settings.server_url = "https://${nodes.nix-zitadel.hostname}/.well-known/openid-configuration";
            }
          ];
        };
      };
    };
  };

  # Support Services (Local to container)
  services.tika.enable = true;
  services.gotenberg = {
    enable = true;
    timeout = "300s";
  };

  # Runtime Secret Injection for OIDC
  systemd.services.paperless-web.script = lib.mkBefore ''
    oidcSecret=$(< ${config.sops.secrets."paperless-creds/oidcSecret".path})

    export PAPERLESS_SOCIALACCOUNT_PROVIDERS=$(
      ${pkgs.jq}/bin/jq <<< "$PAPERLESS_SOCIALACCOUNT_PROVIDERS" \
        --compact-output \
        --arg oidcSecret "$oidcSecret" \
        '.openid_connect.APPS[0].secret = $oidcSecret'
    )
  '';

  # Systemd hardening for Gotenberg
  systemd.services.gotenberg.environment.HOME = "/run/gotenberg";
  systemd.services.gotenberg.serviceConfig = {
    WorkingDirectory = "/run/gotenberg";
    RuntimeDirectory = "gotenberg";
  };

  networking.firewall.allowedTCPPorts = [ nodes.nixpaperless.port ];
}
