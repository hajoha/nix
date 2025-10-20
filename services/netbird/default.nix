{ config, pkgs, ... }:
let
  domain = "johann-hackler.com";
  NETBIRD_DOMAIN = "netbird.${domain}";
  client_id = "netbird";
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
          Secret._secret = "/run/secrets/COTURN";
        };

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
            Audience = client_id;
            Domain = "zitadel.${domain}";
            ClientID = client_id;
            TokenEndpoint = "https://zitadel.${domain}/oauth/v2/token";
            DeviceAuthEndpoint = "https://zitadel.${domain}/oauth/v2/device_authorization";
            Scope = "openid";
            UseIDToken = false;
          };
        };

        ReverseProxy = {
          TrustedHTTPProxies = [ "10.60.0.17/32" ];
          TrustedHTTPProxiesCount = 0;
          TrustedPeers = [ "0.0.0.0/0" ];
        };

        HttpConfig = {
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
            "https://${NETBIRD_DOMAIN}/auth"
            "https://${NETBIRD_DOMAIN}/silent-auth"
          ];
          UseIDToken = false;
        };

        DataStoreEncryptionKey._secret = "/run/secrets/NETBIRD_ENCRYPTION_KEY";
      };
    };

    coturn = {
      enable = true;
      domain = NETBIRD_DOMAIN;
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

      managementServer = "http://localhost:33071";
      settings = {
        AUTH_AUTHORITY = "https://zitadel.${domain}/oauth/v2/authorize";
        NETBIRD_TOKEN_SOURCE = "accessToken";

      };
    };
  };
}
