{
  config,
  pkgs,
  lib,
  nodes,
  keycloakRealm,
  baseDomain,
  ...
}:
{
  # 1. SOPS Configuration
  sops.defaultSopsFile = ./secrets.enc.yaml;
  sops.secrets."immich-env" = {
    # File should contain: DB_PASSWORD
    owner = "immich";
  };
  sops.secrets."immich-oauth-client-secret" = {
    # File should contain: DB_PASSWORD
    owner = "immich";
  };

  services.immich = {
    enable = true;
    host = "0.0.0.0";
    port = nodes.nix-immich.port;
    # Decrypted environment file containing the DB password
    secretsFile = config.sops.secrets."immich-env".path;

    # Media storage location
    mediaLocation = "/var/lib/immich";

    # Database Configuration (pointing to your external Postgres node)
    database = {
      enable = false; # Set to false since you use an external nix-postgres node
      host = nodes.nix-postgres.ip;
      port = nodes.nix-postgres.port;
      name = "immich";
      user = "immich";
    };

    # Redis Configuration
    redis = {
      enable = true; # Set to true if you want a local redis, or false to point elsewhere
    };

    # Main System Settings
    settings = {
      server.externalDomain = "https://${nodes.nix-immich.sub}.${baseDomain}";
      newVersionCheck.enabled = false;
      # Immich OAuth2 (OIDC) Integration
      # Note: Immich uses a specific schema for OIDC in its config
      oauth = {
        enabled = true;
        autoRegister = true;
        issuerUrl = "https://${nodes.nix-keycloak.sub}.${baseDomain}/realms/${keycloakRealm}";
        clientId = "immich";
        clientSecret._secret =  config.sops.secrets."immich-oauth-client-secret".path;
        scope = "openid email profile";
        buttonText = "SSO";
        defaultStorageQuota = 250;
      };
    };
    environment = {
        IMMICH_TRUSTED_PROXIES="${nodes.nix-nginx.ip}";
    };

    # Machine Learning Settings
    machine-learning = {
      enable = true;
    };
  };

  system.stateVersion = "25.11";
}
