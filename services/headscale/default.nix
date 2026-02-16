{
  config,
  pkgs,
  nodes,
  keycloakRealm,
  baseDomain,
  ...
}:
let
  # Construct the Keycloak Issuer URL
  # Standard format: https://<domain>/realms/<realm-name>
  keycloakIssuer = "https://${nodes.nix-keycloak.sub}.${baseDomain}/realms/${keycloakRealm}";
in
{
  # 1. SOPS Secrets Configuration
  sops.defaultSopsFile = ./secrets.enc.yaml;

  sops.secrets = {
    "headplane/OIDC_CLIENT_SECRET" = {
      owner = "headscale";
    };
    "headplane/serverCookieSecret" = {
      owner = "headscale";
    };
    "headplane/integrationAgentPreAuthkeyPath" = {
      owner = "headscale";
    };
    "headplane/oidcHeadscaleApiKey" = {
      owner = "headscale";
    };
  };

  # 2. Core Headscale Service
  services.headscale = {
    enable = true;
    address = "0.0.0.0";
    port = nodes.nix-headscale.port;

    settings = {
      log.level = "info";
      server_url = "https://${nodes.nix-headscale.hostname}.${baseDomain}";
      metrics_listen_addr = "0.0.0.0:9090";

      tls_cert_path = null;
      tls_key_path = null;

      oidc = {
        issuer = keycloakIssuer;
        # Change this to match the 'Client ID' you create in Keycloak
        client_id = "headplane";
        client_secret_path = config.sops.secrets."headplane/OIDC_CLIENT_SECRET".path;
        redirect_url = "https://${nodes.nix-headscale.hostname}.${baseDomain}/oidc/callback";
        scope = [
          "openid"
          "profile"
          "email"
        ];
        extra_params = {
          # 'domain_hint' is Zitadel-specific.
          # You can remove it or use 'kc_idp_hint' if using external IDPs in Keycloak.
        };
      };

      dns = {
        override_local_dns = true;
        base_domain = "vpn.${baseDomain}";
        nameservers = {
          global = [
            nodes.nix-adguard.ip
            "9.9.9.9"
          ];
        };
      };
    };
  };

  # 3. Headplane UI Service
  services.headplane = {
    enable = true;
    debug = true;
    settings = {
      server = {
        host = "0.0.0.0";
        port = 3000;
        cookie_secure = true;
        cookie_secret_path = config.sops.secrets."headplane/serverCookieSecret".path;
      };
      headscale = {
        url = "https://${nodes.nix-headscale.hostname}.${baseDomain}";
      };
      integration.agent = {
        enabled = true;
        pre_authkey_path = config.sops.secrets."headplane/integrationAgentPreAuthkeyPath".path;
      };
      oidc = {
        issuer = keycloakIssuer;
        # Often Headplane and Headscale share a client,
        # but you can create a separate "headplane" client if preferred.
        client_id = "headplane";
        client_secret_path = config.sops.secrets."headplane/OIDC_CLIENT_SECRET".path;
        headscale_api_key_path = config.sops.secrets."headplane/oidcHeadscaleApiKey".path;
        redirect_uri = "https://${nodes.nix-headscale.hostname}.${baseDomain}/admin/oidc/callback";
        disable_api_key_login = true;
        token_endpoint_auth_method = "client_secret_basic";
role_map = {
         "headplane-admin" = "owner";
        };
      };
    };
  };
}