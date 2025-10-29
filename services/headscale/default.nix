# services/headscale/default.nix
{ config, pkgs, ... }:

let
  domain = "headscale.johann-hackler.com";
  zitadelIssuer = "https://zitadel.johann-hackler.com";
in
{
  services.headscale = {
    enable = true;
    # Only listen locally; your existing Nginx handles TLS and proxying.
    address = "0.0.0.0";
    port = 8080;

    settings = {
      server_url = "https://${domain}";
      tls_cert_path = null;
      tls_key_path = null;
      # OIDC (Zitadel)
      oidc = {
        tls_cert_path = "";
        tls_key_path = "";
        issuer = zitadelIssuer;
        client_id = "343314794796875797";
        client_secret_path = "/run/secrets/headplane/OIDC_CLIENT_SECRET";
        redirect_url = "https://headscale.johann-hackler.com/a/oauth_response";
        scope = [
          "openid"
          "profile"
          "email"
        ];
        # allowed_users = [ "user@example.com" ];
        # allowed_domains = [ "example.com" ];
      };
      dns = {
        override_local_dns = true;
        base_domain = "dns.headscale.johann-hackler.com";
        nameservers = {
          global = [
            "10.60.99.16"
            "1.1.1.1"
            "9.9.9.9"
          ];
        };
      };
    };
  };

  # Manage `oidcSecretFile` securely (e.g., `sops`/`agenix`) with owner `headscale:headscale` and mode `0640`.
}
