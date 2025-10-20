{ config, pkgs, ... }:
let
  domain = "johann-hackler.com";
  NETBIRD_DOMAIN = "netbird.${domain}";
  client_id = "342609533283139605";
  #  client_id = "netbird";
in
{
  services.netbird.server = {
    enable = true;
    domain = NETBIRD_DOMAIN;

    management = {
      enable = true;
      enableNginx = false;
      domain = NETBIRD_DOMAIN;
      dnsDomain = domain;
      oidcConfigEndpoint = "https://zitadel.${domain}/.well-known/openid-configuration";
      settings = {
        TURNConfig = {
          Turns = [
            {
              Proto = "udp";
              URI = "turn:${NETBIRD_DOMAIN}:3478";
            }
          ];
          # Must match coturn.passwordFile
          Secret._secret = "/run/secrets/COTURN";
        };

        # Public WS endpoint exposed by your external Nginx
        Signal.URI = "wss://${NETBIRD_DOMAIN}/ws-proxy/signal";

        IdpManagerConfig = {
          ManagerType = "zitadel";
          ClientConfig = {
            Issuer = "https://zitadel.${domain}";
            TokenEndpoint = "https://zitadel.${domain}/oauth/v2/token";
            ClientID = client_id;
            ClientSecret._secret = "/run/secrets/NETBIRD_IDP_MGMT_CLIENT_SECRET";
            GrantType = "client_credentials";
          };

          ExtraConfig = {
            Username = "netbird";
            Password._secret = "/run/secrets/NETBIRD_IDP_MGMT_CLIENT_SECRET";
            ManagementEndpoint = "https://zitadel.${domain}/management/v1";
          };
          Auth0ClientCredentials = null;

        };

        DeviceAuthorizationFlow = {
          Provider = "zitadel";
          ProviderConfig = {
            Audience = "netbird";
            Domain = domain;
            ClientID = "netbird";
            TokenEndpoint = "https://zitadel.${domain}/oauth/v2/token";
            DeviceAuthEndpoint = "https://zitadel.${domain}/oauth/v2/device_authorization";
            Scope = "openid";
            UseIDToken = false;
          };
        };
        ReverseProxy = {
          TrustedHTTPProxies = [];
          TrustedHTTPProxiesCount = 0;
          TrustedPeers = [ "0.0.0.0/0" ];
        };

        HttpConfig = {
#          Address = "127.0.0.1:${builtins.toString cfg.port}";
          IdpSignKeyRefreshEnabled = true;
          OIDCConfigEndpoint = "https://zitadel.${domain}/.well-known/openid-configuration";
        };

        PKCEAuthorizationFlow.ProviderConfig = {
          Audience = client_id;
          ClientID = client_id;
          AuthorizationEndpoint = "https://zitadel.${domain}/oauth/v2/authorize";
          TokenEndpoint = "https://zitadel.${domain}/oauth/v2/token";
          DeviceAuthEndpoint = "https://zitadel.${domain}/oauth/v2/device_authorization";
          RedirectURLs = [
            "http://localhost:53000/"
            "https://netbird.johann-hackler.com/auth"
            "https://netbird.johann-hackler.com/silent-auth"

          ];
          UseIDToken = false;
        };

        DataStoreEncryptionKey._secret = "/run/secrets/NETBIRD_ENCRYPTION_KEY";
      };
    };

    coturn = {
      enable = true;
      domain = NETBIRD_DOMAIN;
      # Must match TURNConfig.Secret above
      passwordFile = "/run/secrets/COTURN";
    };

    signal = {
      enable = true;
      domain = NETBIRD_DOMAIN;
      enableNginx = false;
    };

    dashboard = {
      enable = true;
      enableNginx = false;
      domain = NETBIRD_DOMAIN;

      managementServer = "https://${NETBIRD_DOMAIN}";
      settings = {
        AUTH_AUTHORITY = "https://zitadel.${domain}";
        AUTH_SUPPORTED_SCOPES = "openid profile email offline_access api";
        AUTH_REDIRECT_URI = "/auth";
        AUTH_SILENT_REDIRECT_URI = "/silent-auth";
        DISABLE_LETSENCRYPT = "true";

        AUTH_OIDC_CONFIGURATION_ENDPOINT = "https://zitadel.johann-hackler.com/.well-known/openid-configuration";
        USE_AUTH0 = false;
        AUTH_AUDIENCE = "netbird";
        AUTH_CLIENT_ID = "netbird";

        AUTH_DEVICE_AUTH_PROVIDER = "hosted";
        AUTH_DEVICE_AUTH_CLIENT_ID = client_id;
        AUTH_DEVICE_AUTH_AUDIENCE = client_id;

        MGMT_IDP = "zitadel";
        IDP_MGMT_EXTRA_MANAGEMENT_ENDPOINT = "https://zitadel.johann-hackler.com/management/v1";
        MGMT_IDP_SIGNKEY_REFRESH = true;

      };
    };
  };
}
