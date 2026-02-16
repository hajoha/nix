{ config, pkgs, nodes, baseDomain, ... }:

{

users.users.keycloak = {
    group = "keycloak";
    isNormalUser = true;
  };
  users.groups.keycloak = {};
  # 1. SOPS Secret Configuration
sops.secrets."keycloak-env" = {
    sopsFile = ./secrets.enc.yaml;
    owner = "keycloak";
    group = "keycloak";
    mode = "0440";
    key = "keycloak-env";
    # This prevents the "unknown user" error during activation
    restartUnits = [ "keycloak.service" ];
  };

  # 2. Keycloak Service Configuration
  services.keycloak = {
    enable = true;
    package = pkgs.keycloak;

    database = {
      type = "postgresql";
      host = nodes.nix-postgres.ip;
      port = nodes.nix-postgres.port;
      name = "keycloak";
      username = "keycloak";

      passwordFile = config.sops.secrets."keycloak-env".path;

      createLocally = false;
      useSSL = false;
    };

    settings = {
      http-host = "0.0.0.0";
      http-port = nodes.nix-keycloak.port;

      hostname = "https://${nodes.nix-keycloak.sub}.${baseDomain}";
      http-relative-path = "/";

      proxy-headers = "xforwarded";
      http-enabled = true;
      hostname-strict = true;
      hostname-backchannel-dynamic = true;

      bootstrap-admin-username = "admin";

      # Logging
      log-level = "info";
    };
  };

  # 3. Systemd Override for LXC Compatibility
systemd.services.keycloak = {
    # This creates the directory before the service starts
    preStart = ''
      mkdir -p /var/lib/keycloak
      chown keycloak:keycloak /var/lib/keycloak
    '';

    serviceConfig = {
      # 1. Keep our previous LXC fix
      LoadCredential = [ "" ];
      EnvironmentFile = [ config.sops.secrets."keycloak-env".path ];
      BindReadOnlyPaths = [ "/run/secrets" ];
      Environment = [ "CREDENTIALS_DIRECTORY=/run/secrets" ];

      # 2. Fix the NAMESPACE error
      # Tell systemd not to try and create a private /tmp or mount namespace
      # which often fails in unprivileged LXC containers.
      PrivateTmp = false;
      ProtectSystem = "full";
      ProtectHome = "read-only";

      # Ensure the state directory is handled simply
      StateDirectory = "keycloak";
      StateDirectoryMode = "0700";
    };
  };

  system.stateVersion = "25.11";
}