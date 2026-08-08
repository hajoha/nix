{
  config,
  lib,
  pkgs,
  inputs,
  nodes,
  baseDomain,
  keycloakRealm,
  ...
}:
let
  node = nodes.nix-sure;
  domain = "${node.sub}.${baseDomain}"; # sure.johann-hackler.com
  surePkgs = inputs.nixpkgs-sure.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  sureUnits = [
    "sure-web.service"
    "sure-sidekiq.service"
    "sure-init-db.service"
  ];
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

      # Without nginx there's nothing serving ${pkgs.sure}/public, so Rails
      # has to do it itself. Omitting this gives you an unstyled app: 404s on
      # every /assets/* request.
      RAILS_SERVE_STATIC_FILES = "true";

      # Make sure Puma listens on the bridge, not just loopback.
      BINDING = "0.0.0.0";

      OIDC_KEYCLOAK_ISSUER = "https://${nodes.nix-keycloak.sub}.${baseDomain}/realms/${keycloakRealm}";
      OIDC_KEYCLOAK_CLIENT_ID = "sure";
    };
  };

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

}
