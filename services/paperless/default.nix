{
  config,
  pkgs,
  lib,
  ...
}:

{
  services.paperless = {
    enable = true;
    consumptionDirIsPublic = true;
    address = "0.0.0.0";
    port = 8000;
    environmentFile = config.sops.secrets."paperless-creds/env".path;
    settings = {
      PAPERLESS_CONSUMER_IGNORE_PATTERN = [
        ".DS_STORE/*"
        "desktop.ini"
      ];
      PAPERLESS_TIKA_ENABLED = "1";
      PAPERLESS_TIKA_GOTENBERG_ENDPOINT = "http://localhost:${toString config.services.gotenberg.port}";
      PAPERLESS_TIKA_ENDPOINT = "http://${config.services.tika.listenAddress}:${toString config.services.tika.port}";

      PAPERLESS_OCR_LANGUAGE = "deu+eng";
      PAPERLESS_DISABLE_REGULAR_LOGIN = "True";
      PAPERLESS_REDIRECT_LOGIN_TO_SSO = "True";

      PAPERLESS_OCR_USER_ARGS = {
        optimize = 1;
        pdfa_image_compression = "lossless";
      };
      PAPERLESS_URL = "https://paperless.johann-hackler.com";
      PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
      PAPERLESS_SOCIALACCOUNT_PROVIDERS = builtins.toJSON {
        openid_connect = {
          OAUTH_PKCE_ENABLED = "True";
          APPS = [
            rec {
              provider_id = "zitadel";
              name = "Zitadel";
              client_id = "351648507242807573";
              # secret will be added dynamically
              #secret = "";
              settings.server_url = "https://zitadel.johann-hackler.com/.well-known/openid-configuration";
            }
          ];
        };

      };
    };

  };

  services.tika = {
    enable = true;
  };
  services.gotenberg = {
    enable = true;
    timeout = "300s";
  };
  systemd.services.gotenberg.environment = {
    HOME = "/run/gotenberg";
  };
  systemd.services.gotenberg.serviceConfig = {
    WorkingDirectory = "/run/gotenberg";
    RuntimeDirectory = "gotenberg";
  };

  systemd.services.paperless-web.script = lib.mkBefore ''
    oidcSecret=$(< ${config.sops.secrets."paperless-creds/oidcSecret".path})

    export PAPERLESS_SOCIALACCOUNT_PROVIDERS=$(
      ${pkgs.jq}/bin/jq <<< "$PAPERLESS_SOCIALACCOUNT_PROVIDERS" \
        --compact-output \
        --arg oidcSecret "$oidcSecret" \
        '.openid_connect.APPS[0].secret = $oidcSecret'
    )
  '';
  networking.firewall.allowedTCPPorts = [
    8000
  ];
}
