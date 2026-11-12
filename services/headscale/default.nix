{
  config,
  pkgs,
  ...
}:

let
  inherit (config.homelab) nodes sso;
  baseDomain = config.homelab.domain;
  # Construct the Keycloak Issuer URL
  # Standard format: https://<domain>/realms/<realm-name>
  keycloakIssuer = sso.issuer;
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
      server_url = nodes.nix-headscale.url;
      metrics_listen_addr = "0.0.0.0:9090";

      tls_cert_path = null;
      tls_key_path = null;

      oidc = {
        issuer = keycloakIssuer;
        # Change this to match the 'Client ID' you create in Keycloak
        client_id = "headplane";
        client_secret_path = config.sops.secrets."headplane/OIDC_CLIENT_SECRET".path;
        redirect_url = "${nodes.nix-headscale.url}/oidc/callback";
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

            "9.9.9.9"
          ];
          split."hackler.io" = [ nodes.nix-adguard.ip ];
        };
      };
    };
  };

  # 3. Headplane UI Service
  # 3. Headplane UI Service
  services.headplane = {
    enable = true;
    debug = true;

    settings = {
      server = {
        host = "0.0.0.0"; # see point 3
        port = 3000;
        base_url = nodes.nix-headscale.url;
        cookie_secure = true;
        cookie_secret_path = config.sops.secrets."headplane/serverCookieSecret".path;
      };
      headscale = {
        url = nodes.nix-headscale.url;
        # Provides the base domain so Headplane can construct /admin/oidc/callback
        public_url = nodes.nix-headscale.url;
        api_key_path = config.sops.secrets."headplane/oidcHeadscaleApiKey".path;
      };

      oidc = {
        issuer = keycloakIssuer;
        client_id = "headplane";
        client_secret_path = config.sops.secrets."headplane/OIDC_CLIENT_SECRET".path;
        disable_api_key_login = true;
        token_endpoint_auth_method = "client_secret_basic";
      };
    };
  };
}
