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
in

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
    "env" = {
      sopsFile = ./postgres.enc.yaml;
      key = "password";
    };
  };
  sops.templates.".env" = {
    owner = "paperless";

    content = ''
      ${config.sops.placeholder."paperless-creds/env"}
      PAPERLESS_DBPASS=${config.sops.placeholder."env"}
      PAPERLESS_SOCIALACCOUNT_PROVIDERS='{"openid_connect": {"OAUTH_PKCE_ENABLED": "True", "APPS": [{"provider_id": "keycloak", "name": "SSO", "client_id": "paperless", "secret": "${
        config.sops.placeholder."paperless-creds/oidcSecret"
      }", "settings": {"server_url": "${keycloakUrl}/realms/${keycloakRealm}/.well-known/openid-configuration"}}]}}'
    '';
  };

  services.paperless = {
    enable = true;
    address = "0.0.0.0";
    port = nodes.nix-paperless.port;
    consumptionDirIsPublic = true;

    # Environment file for DB_PASS and other standard secrets
    environmentFile = config.sops.templates.".env".path;

    settings = {
      PAPERLESS_URL = "https://${nodes.nix-paperless.hostname}.${baseDomain}";

      # Database connection to central Postgres
      PAPERLESS_DBHOST = nodes.nix-postgres.ip;
      PAPERLESS_DBPORT = toString nodes.nix-postgres.port;
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

      PAPERLESS_DISABLE_REGULAR_LOGIN = "True";
      PAPERLESS_REDIRECT_LOGIN_TO_SSO = "True";
      PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
      PAPERLESS_SOCIALACCOUNT_ADAPTER = "allauth.socialaccount.adapter.DefaultSocialAccountAdapter";

    };
  };

  # Support Services (Local to container)
  services.tika.enable = true;
  services.gotenberg = {
    enable = true;
    timeout = "300s";
  };

  # Systemd hardening for Gotenberg
  systemd.services.gotenberg.environment.HOME = "/run/gotenberg";
  systemd.services.gotenberg.serviceConfig = {
    WorkingDirectory = "/run/gotenberg";
    RuntimeDirectory = "gotenberg";
  };

  networking.firewall.allowedTCPPorts = [ nodes.nix-paperless.port ];
}
