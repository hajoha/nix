{ config, pkgs, ... }:
let
    domain = "johann-hackler.com";
    NETBIRD_DOMAIN = "netbird.${domain}";
    client_id = "342506572867502101";
in
{
  services.netbird.server = {
    enable = true;
    domain = NETBIRD_DOMAIN;



    management = {
      oidcConfigEndpoint = "https://zitadel.${domain}/.well-known/openid-configuration";
      settings = {
        TURNConfig = {
          Turns = [
            {
              Proto = "udp";
              URI = "turn:${NETBIRD_DOMAIN}:3478";
              Username = "netbird";
              Password._secret = "/run/secrets/PASSWORD_COTURN";
            }
          ];
          Secret._secret = "/run/secrets/TURN_SECRET";
        };
        Signal.URI = "${NETBIRD_DOMAIN}:443";
        IdpManagerConfig = {
          ManagerType = "zitadel";
          ClientConfig = {
            Issuer = "https://zitadel.${domain}";
            TokenEndpoint = "https://zitadel.${domain}/oauth/v2/token";
            ClientID = client_id;
            ClientSecret._secret = "/run/secrets/NETBIRD_IDP_MGMT_CLIENT_SECRET";

          };
          ExtraConfig = {
            Password._secret = "/run/secrets/NETBIRD_IDP_MGMT_CLIENT_SECRET";
            Username = "netbird";
            ManagementEndpoint = "https://zitadel.${domain}/management/v1";
          };
          Auth0ClientCredentials = null;
        };

        HttpConfig = {
          AuthAudience = client_id;
          AuthUserIDClaim = "sub";
        };

        PKCEAuthorizationFlow.ProviderConfig = {
          Audience = client_id;
          ClientID = client_id;
          ClientSecret._secret = "/run/secrets/NETBIRD_IDP_MGMT_CLIENT_SECRET";
          AuthorizationEndpoint = "https://zitadel.${domain}";
          TokenEndpoint = "https://zitadel.${domain}";
          RedirectURLs = [ "http://localhost:53000" ];
        };
        DataStoreEncryptionKey._secret = "/run/secrets/NETBIRD_ENCRYPTION_KEY";
      };
    };

    coturn = {
      enable = true;
      passwordFile = "/run/secrets/COTURN";
    };

    dashboard = {
      enableNginx = true;
      domain = "dashboard.${domain}";
      settings = {
        AUTH_AUTHORITY = "https://zitadel.${domain}";
        AUTH_SUPPORTED_SCOPES = "openid profile email offline_access api";
        AUTH_AUDIENCE = client_id;
        AUTH_CLIENT_ID = client_id;
      };
    };
  };
}
