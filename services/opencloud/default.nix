{ config, pkgs, ... }:
{
  services.opencloud = {
    enable = true;
    url = "https://opencloud.johann-hackler.com";
    address = "0.0.0.0";
    settings = {
      OC_DOMAIN = "opencloud.johann-hackler.com";
    };
    environment = {
      PROXY_CSP_CONFIG_FILE_LOCATION = "/etc/opencloud/csp.yaml";
      OC_OIDC_ISSUER = "https://zitadel.johann-hackler.com/";
      EXTERNAL_OIDC_DOMAIN = "zitadel.johann-hackler.com";
      PROXY_OIDC_REWRITE_WELLKNOWN = "true";
      OC_INSECURE = "true";
      WEB_OIDC_CLIENT_ID = "344354127221948437";
      PROXY_OIDC_ACCESS_TOKEN_VERIFY_METHOD = "none";
      PROXY_AUTOPROVISION_ACCOUNTS = "true";
      PROXY_USER_OIDC_CLAIM = "sub";
      PROXY_USER_CS3_CLAIM = "username";
      PROXY_AUTOPROVISION_CLAIM_EMAIL = "email";
      PROXY_AUTOPROVISION_CLAIM_DISPLAYNAME = "name";
      PROXY_AUTOPROVISION_CLAIM_GROUPS = "groups";
      PROXY_AUTOPROVISION_CLAIM_USERNAME = "sub";
      OC_EXCLUDE_RUN_SERVICES = "idp";
      OC_ADMIN_USER_ID = "";
      GRAPH_ASSIGN_DEFAULT_USER_ROLE = "false";
      GRAPH_USERNAME_MATCH = "none";
      GRAPH_LDAP_SERVER_WRITE_ENABLED = "true";
      OC_LOG_LEVEL = "debug";
    };
  };

  environment.etc."opencloud/csp.yaml" = {
    mode = "0644";
    text = ''
      directives:
        default-src:
          - "'none'"
        child-src:
          - "'self'"
        connect-src:
          - "'self'"
          - "'blob:'"
          - "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/"
          - "https://update.opencloud.eu/"
          - "https://zitadel.johann-hackler.com"
        font-src:
          - "'self'"
        frame-ancestors:
          - "'self'"
        frame-src:
          - "'self'"
          - "'blob:'"
          - "https://embed.diagrams.net/"
          - "https://docs.opencloud.eu"
          - "https://zitadel.johann-hackler.com"
        img-src:
          - "'self'"
          - "'data:'"
          - "'blob:'"
          - "https://tile.openstreetmap.org/"
          - "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/"
          - "https://zitadel.johann-hackler.com"
        manifest-src:
          - "'self'"
        media-src:
          - "'self'"
        object-src:
          - "'self'"
          - "'blob:'"
        script-src:
          - "'self'"
          - "'unsafe-inline'"
          - "'unsafe-hashes'"
          - "'unsafe-eval'"
          - "https://zitadel.johann-hackler.com"
        style-src:
          - "'self'"
          - "'unsafe-inline'"
          - "'unsafe-hashes'"
    '';
  };

  networking.firewall.allowedTCPPorts = [ 9200 ];
}
