# Tranquil PDS — atproto Personal Data Server (your identity for Tangled,
# Bluesky & co). Module comes from the `tranquil` flake input, see flake.nix.
#
# Traffic:  internet → nix-nginx (TLS for pds.<domain> + *.pds.<domain>) → :3000 here
# Database: nix-postgres ("tranquil" is in servicesWithDB there)
# Secrets:  ./postgres.enc.yaml  DB password, shared with nix-postgres (key `password`)
#           ./secrets.enc.yaml   app secrets, SSO, SMTP
{
  config,
  nodes,
  baseDomain,
  keycloakRealm,
  ...
}:
let
  node = nodes.nix-tranquil;
  pg = nodes.nix-postgres;
  kc = nodes.nix-keycloak;

  pdsHost = "${node.sub}.${baseDomain}";
  keycloakIssuer = "https://${kc.sub}.${baseDomain}/realms/${keycloakRealm}";

  inherit (config.sops) placeholder;

  appSecret = key: {
    sopsFile = ./secrets.enc.yaml;
    inherit key;
  };
in
{
  # Pull prebuilt tranquil-pds + frontend from upstream CI instead of compiling.
  nix.settings = {
    substituters = [ "https://tranquil.cachix.org" ];
    trusted-public-keys = [ "tranquil.cachix.org-1:PoO+mGL6a6LcJiPakMDHN4E218/ei/7v2sxeDtNkSRg=" ];
  };

  # ./postgres.enc.yaml (plaintext before `sops -e`), same shape as your other services:
  #
  #   password: <openssl rand -hex 32>    # hex: it goes into a URL, no escaping needed
  #
  # ./secrets.enc.yaml (plaintext before `sops -e`):
  #
  #   jwt_secret: <openssl rand -base64 48>
  #   dpop_secret: <openssl rand -base64 48>
  #   master_key: <openssl rand -base64 48>
  #   sso_client_secret: <Keycloak client "tranquil-pds" → Credentials tab>
  #   smtp_host: <smtp host>
  #   smtp_username: <smtp user>
  #   smtp_password: <smtp password>
  #
  # master_key encrypts the per-account signing keys in the database.
  # Keep an offline copy: without it, a database restore is useless.
  sops.secrets = {
    "tranquil/db-password" = {
      sopsFile = ./postgres.enc.yaml;
      key = "password";
    };
    "tranquil/jwt-secret" = appSecret "jwt_secret";
    "tranquil/dpop-secret" = appSecret "dpop_secret";
    "tranquil/master-key" = appSecret "master_key";
    "tranquil/sso-client-secret" = appSecret "sso_client_secret";
    "tranquil/smtp-host" = appSecret "smtp_host";
    "tranquil/smtp-username" = appSecret "smtp_username";
    "tranquil/smtp-password" = appSecret "smtp_password";
  };

  # Environment file assembled from the secrets above. Env vars take
  # precedence over config.toml, so these override `settings` at runtime.
  sops.templates."tranquil-pds.env" = {
    content = ''
      DATABASE_URL=postgresql://tranquil:${
        placeholder."tranquil/db-password"
      }@${pg.ip}:${toString pg.port}/tranquil
      JWT_SECRET=${placeholder."tranquil/jwt-secret"}
      DPOP_SECRET=${placeholder."tranquil/dpop-secret"}
      MASTER_KEY=${placeholder."tranquil/master-key"}
      SSO_OIDC_ENABLED=true
      SSO_OIDC_CLIENT_SECRET=${placeholder."tranquil/sso-client-secret"}
      MAIL_SMARTHOST_HOST=${placeholder."tranquil/smtp-host"}
      MAIL_SMARTHOST_USERNAME=${placeholder."tranquil/smtp-username"}
      MAIL_SMARTHOST_PASSWORD=${placeholder."tranquil/smtp-password"}
    '';
    restartUnits = [ "tranquil-pds.service" ];
  };
  networking.hosts.${nodes.nix-nginx.ip} = [
    pdsHost
    "${kc.sub}.${baseDomain}"
  ];

  services.tranquil-pds = {
    enable = true;

    # Postgres runs on nix-postgres, not in this container.
    database.createLocally = false;

    environmentFiles = [ config.sops.templates."tranquil-pds.env".path ];

    settings = {
      server = {
        hostname = pdsHost;
        allow_private_fetch = true;
        # Default is [::1]; nginx lives in another LXC, so listen on the LAN.
        # The port is opened in network.nix like your other nodes.
        host = "0.0.0.0";
        inherit (node) port;

        # Handles are served as <name>.pds.<domain>. nginx terminates TLS with
        # a wildcard cert, so Caddy's on-demand TLS endpoint isn't needed.
        enable_caddy_on_demand_tls = false;

        # The first invite code is printed once in `journalctl -u tranquil-pds`.
        invite_code_required = true;

        contact_email = "info@${baseDomain}";

        # trusted_proxy_count defaults to 1 (nix-nginx). Raise it if another
        # proxy that appends X-Forwarded-For sits in front of nix-nginx.
        # trusted_proxy_count = 2;
      };

      # Password-less on purpose: this is only what the build-time config
      # validation sees. The real URL comes from DATABASE_URL in the env file.
      database.url = "postgresql://tranquil@${pg.ip}:${toString pg.port}/tranquil";

      # Needed for verification codes and PLC operations.
      # SMTP host and credentials come from the env file (MAIL_SMARTHOST_*);
      # port defaults to 587 with STARTTLS.
      email = {
        from_address = "pds@${baseDomain}";
        from_name = "PDS ${baseDomain}";
      };

      # Login to the PDS via Keycloak (confidential OIDC client "tranquil-pds").
      # `enabled` is switched on via SSO_OIDC_ENABLED in the env file, next to
      # the client secret: the module validates config.toml at build time with
      # only the [secrets] section ignored, and an enabled provider without its
      # secret may fail that check.
      sso.oidc = {
        issuer = keycloakIssuer;
        client_id = "tranquil";
        display_name = "SSO";
      };

      # Strongly recommended: a PLC recovery key that only you hold (offline),
      # so you can recover or move your identity if this PDS ever dies.
      # Public did:key only, so it's fine in the nix store.
      # secrets.plc_rotation_key = "did:key:z...";
    };
  };
}
