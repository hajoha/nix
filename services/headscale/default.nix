{ config, pkgs, nodes, baseDomain, ... }:

{
  # 1. SOPS Secrets Configuration
  # We define both Headscale and Headplane secrets here
  sops.defaultSopsFile = ./secrets.enc.yaml;

  sops.secrets = {
    "headplane/OIDC_CLIENT_SECRET" = { owner = "headscale"; };
    "headplane/serverCookieSecret" = { owner = "headscale"; };
    "headplane/integrationAgentPreAuthkeyPath" = { owner = "headscale"; };
    "headplane/oidcHeadscaleApiKey" = { owner = "headscale"; };
  };

  # 2. Core Headscale Service
  services.headscale = {
    enable = true;
    address = "0.0.0.0";
    port = nodes.nixheadscale.port;

    settings = {
      log.level = "info";
      server_url = "https://${nodes.nixheadscale.hostname}";
      metrics_listen_addr = "0.0.0.0:9090";

      tls_cert_path = null;
      tls_key_path = null;

      oidc = {
        issuer = "https://${nodes.nixzitadel.hostname}";
        client_id = "343314794796875797";
        client_secret_path = config.sops.secrets."headplane/OIDC_CLIENT_SECRET".path;
        redirect_url = "https://${nodes.nixheadscale.hostname}/oidc/callback";
        scope = [ "openid" "profile" "email" ];
        extra_params = {
          domain_hint = baseDomain;
        };
      };

      dns = {
        override_local_dns = true;
        base_domain = "vpn.${baseDomain}";
        nameservers = {
          global = [
            nodes.nixadguard.ip
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
        cookie_secure = true; # Nginx handles SSL
        cookie_secret_path = config.sops.secrets."headplane/serverCookieSecret".path;
      };
      headscale = {
        url = "https://${nodes.nixheadscale.hostname}";
      };
      integration.agent = {
        enabled = true;
        pre_authkey_path = config.sops.secrets."headplane/integrationAgentPreAuthkeyPath".path;
      };
      oidc = {
        issuer = "https://${nodes.nixzitadel.hostname}";
        client_id = "343314794796875797";
        client_secret_path = config.sops.secrets."headplane/OIDC_CLIENT_SECRET".path;
        headscale_api_key_path = config.sops.secrets."headplane/oidcHeadscaleApiKey".path;
        redirect_uri = "https://${nodes.nixheadscale.hostname}/admin/oidc/callback";
        disable_api_key_login = false;
        token_endpoint_auth_method = "client_secret_basic";
      };
    };
  };

  # 4. Networking
  networking.firewall.allowedTCPPorts = [
    nodes.nixheadscale.port # 8080
    3000                    # Headplane UI
    9090                    # Metrics
  ];
}