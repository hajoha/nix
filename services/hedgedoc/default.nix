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
  sops.secrets."env" = {
    # File should contain: CMD_DB_PASSWORD, CMD_OAUTH2_CLIENT_ID, CMD_OAUTH2_CLIENT_SECRET
    owner = "hedgedoc";
  };
  sops.secrets."pg-password" = {
    owner = "hedgedoc";
    key = "password";
    sopsFile = ./postgres.enc.yaml;
  };

  sops.templates.".env" = {
    owner = "hedgedoc";
    # Use .placeholder to reference the actual decrypted values
    content = ''
      ${config.sops.placeholder.env}
      CMD_DB_PASSWORD=${config.sops.placeholder."pg-password"}
    '';
  };

  services.hedgedoc = {
    enable = true;
    # Decrypted environment file containing secrets
    environmentFile = config.sops.templates.".env".path;

    settings = {
      # Networking & Branding
      host = "0.0.0.0";
      port = nodes.nix-hedgedoc.port;
      domain = "${nodes.nix-hedgedoc.hostname}.${baseDomain}";

      # SSL handled by Nginx proxy
      protocolUseSSL = true;
      useSSL = false;
      urlAddPort = false;

      # Access Controls
      allowEmailRegister = false;
      allowGravatar = false;
      allowAnonymous = true;
      allowAnonymousEdits = true;
      allowFreeURL = true;
      disableNoteCreation = false;
      defaultPermission = "freely";

      allowOrigin = [
        "localhost"
        "${nodes.nix-hedgedoc.hostname}.${baseDomain}"
      ];

      # Database connection using the nix-postgres node
      db = {
        database = "hedgedoc";
        dialect = "postgresql";
        host = nodes.nix-postgres.ip;
        port = nodes.nix-postgres.port;
        username = "hedgedoc";
        # Password is injected via CMD_DB_PASSWORD in environmentFile
      };

      # OAuth2 (Zitadel Integration)
      oauth2 = {
        enabled = true;
        provider = "generic";
        # Public URLs require the FQDN for browser redirects via Nginx
        baseURL = "https://${nodes.nix-keycloak.sub}.${baseDomain}/realms/${keycloakRealm}";
        authorizationURL = "https://${nodes.nix-keycloak.sub}.${baseDomain}/realms/${keycloakRealm}/protocol/openid-connect/auth";
        tokenURL = "https://${nodes.nix-keycloak.sub}.${baseDomain}/realms/${keycloakRealm}/protocol/openid-connect/token";
        userProfileURL = "https://${nodes.nix-keycloak.sub}.${baseDomain}/realms/${keycloakRealm}/protocol/openid-connect/userinfo";
        scope = "openid email profile";
        userProfileDisplayNameAttr = "preferred_username";
        userProfileEmailAttr = "email";
        userProfileUsernameAttr = "preferred_username";
      };

      debug = true;
      email = false;
    };
  };

  # Firewall is now handled by mkLXC + network.nix
  system.stateVersion = "25.11";
}
