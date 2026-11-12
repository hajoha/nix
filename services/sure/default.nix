{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  inherit (config.homelab) nodes sso;
  node = nodes.nix-sure;
  domain = node.fqdn; # sure.johann-hackler.com
  surePkgs = inputs.nixpkgs-sure.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  sureUnits = [
    "sure-web.service"
    "sure-sidekiq.service"
    "sure-init-db.service"
  ];
  ingSyncEnv = pkgs.python3.withPackages (ps: [
    ps.fints
    ps.requests
  ]);
  ingSync = pkgs.writeScriptBin "ing-sync" ''
    #!${ingSyncEnv}/bin/python3
    ${builtins.readFile ./ing-sync.py}
  '';
in
{
  # The module isn't in nixos-unstable's module-list, so import the file directly.
  # No `disabledModules` needed — nothing upstream to clash with yet.
  imports = [
    "${inputs.nixpkgs-sure}/nixos/modules/services/web-apps/sure.nix"
  ];

  # ── secrets ───────────────────────────────────────────────────────────────

  # Read by systemd as root via LoadCredential → stays root-owned, `sure` never
  # needs read access.
  sops.secrets."sure-secret-key-base" = {
    format = "yaml";
    sopsFile = ./secrets.enc.yaml;
    mode = "0400";
    restartUnits = sureUnits;
  };

  # Multiline KEY=value block. Consumed two ways:
  #   1. EnvironmentFile= on the units (systemd parses it as root, merges into
  #      the env before dropping to User=sure)
  #   2. `source`d by the sure-rails / sure-console CLI wrapper, which runs as
  #      `sure` → hence owner/group below.
  # No `export` prefixes, no shell syntax: systemd would reject those lines.
  sops.secrets."sure-env" = {
    format = "yaml";
    sopsFile = ./secrets.enc.yaml;
    owner = "sure";
    group = "sure";
    mode = "0440";
    restartUnits = sureUnits;
  };

  # Same file nix-postgres decrypts; encrypted to both host keys via .sops.yaml.
  # Reaches Rails as POSTGRES_PASSWORD through LoadCredential + systemd-creds.
  sops.secrets."postgres-password" = {
    format = "yaml";
    sopsFile = ./postgres.enc.yaml;
    key = "password";
    mode = "0400";
    restartUnits = sureUnits;
  };

  # ── app ───────────────────────────────────────────────────────────────────
  services.sure = {
    enable = true;
    package = surePkgs.sure;
    localDomain = domain;

    # Rails on 3001; container-local nginx fronts it on node.port (3000) so
    # ${pkgs.sure}/public is served without round-tripping through Rails.
    # Rails binds node.port directly now — no local nginx in front.
    webPort = node.port; # 3000

    forceSSL = false;
    assumeSSL = true;

    configureNginx = false; # ← was true
    automaticMigrations = true;
    sidekiqThreads = 5;

    secretKeyBaseFile = config.sops.secrets."sure-secret-key-base".path;
    extraEnvFiles = [ config.sops.secrets."sure-env".path ];

    redis.createLocally = true; # unix socket (port = 0 default)

    database = {
      createLocally = false;
      host = nodes.nix-postgres.ip; # 10.60.1.20
      port = nodes.nix-postgres.port; # 5432
      name = "sure";
      user = "sure";
      passwordFile = config.sops.secrets."postgres-password".path;
    };

    # Non-secret values only — these end up in the unit file in the store and
    # in `systemctl show`. The client secret lives in sure-env instead.
    environment = {
      APP_DOMAIN = domain;
      REQUIRE_INVITE_CODE = "true";
      RAILS_SERVE_STATIC_FILES = "true";
      BINDING = "0.0.0.0";

      OIDC_ISSUER = sso.issuer;
      OIDC_CLIENT_ID = "sure";
      OIDC_REDIRECT_URI = "https://${domain}/auth/openid_connect/callback";
      OIDC_BUTTON_LABEL = "SSO Login";
      OIDC_BUTTON_ICON = "key";
      AUTH_JIT_MODE = "create_and_link";
      AUTH_LOCAL_LOGIN_ENABLED = "false";
      AUTH_LOCAL_ADMIN_OVERRIDE_ENABLED = "false";
      # ALLOWED_OIDC_DOMAINS = "hackler.io";
    };
  };
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "sure-rails-env" ''
      set -a
      . ${config.sops.secrets."sure-env".path}
      set +a
      exec ${lib.getExe pkgs.sudo} -E -u sure \
        ${config.services.sure.package.rubyEnv}/bin/bundle exec rails "$@"
    '')
  ];
  # sure-init-db only orders on network.target, but postgres lives in another
  # container — retry instead of failing the whole activation on a cold boot.
  systemd.services.sure-init-db.serviceConfig = {
    Restart = "on-failure";
    RestartSec = 15;
  };
  systemd.services.sure-init-db.unitConfig = {
    StartLimitIntervalSec = 300;
    StartLimitBurst = 10;
  };

  # KEY=value lines, read by systemd as root before dropping to `sure`.
  sops.secrets."ing-sync-env" = {
    format = "yaml";
    sopsFile = ./secrets.enc.yaml;
    mode = "0400";
    restartUnits = [ "ing-sync.service" ];
  };

  systemd.services.ing-sync = {
    description = "Pull ING transactions via FinTS into Sure";
    after = [
      "network-online.target"
      "sure-web.service"
    ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "sure";
      Group = "sure";
      EnvironmentFile = config.sops.secrets."ing-sync-env".path;
      StateDirectory = "ing-sync";
      StateDirectoryMode = "0700";
      ExecStart = "${ingSync}/bin/ing-sync";
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
    };
    environment = {
      SURE_URL = "http://127.0.0.1:${toString node.port}";
      FINTS_BLZ = "50010517";
      FINTS_ENDPOINT = "https://fints.ing.de/fints/";
      SYNC_DAYS = "85";
      FINTS_PRODUCT_ID = "NOTREGISTERED";
    };
  };

  systemd.timers.ing-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
  };

}
