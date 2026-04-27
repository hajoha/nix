{
  config,
  lib,
  pkgs,
  nodes,
  keycloakRealm,
  baseDomain,
  ...
}:
{

  sops.secrets."opencloud-env" = {
    format = "yaml";
    sopsFile = ./secrets.enc.yaml;
    owner = "opencloud";
    group = "opencloud";
    mode = "0440";
  };
  services.collabora-online = {
    enable = true;
    port = 9980;
    settings = {
      wopi = {
        url = "https://collabora.${baseDomain}";
      };
      ssl = {
        enable = false;
        termination = true;
      };
      # This allows your domain to request documents
      # Note the double-backslash: Nix requires it to pass a single backslash to Nginx/Collabora
      storage.wopi.host = [
        "^opencloud\\.johann-hackler\\.com$"
        "^collabora\\.johann-hackler\\.com$"
      ];
      net = {
        listen = "any";
        # Frame ancestors tells the browser which sites are allowed to iframe Collabora
        frame_ancestors = [
          "opencloud.${baseDomain}"
          "collabora.${baseDomain}"
        ];
      };

      storage.wopi.alias_groups = {
        mode = "groups";
        group = [
          {
            # This covers the primary domain and any port variation
            host = [ "https://opencloud\\.johann-hackler\\.com(:[0-9]+)?" ];
            allow = true;
          }
        ];
      };
    };

  };

  services.opencloud = {
    enable = true;
    url = "https://opencloud.${baseDomain}";
    address = "0.0.0.0";
    port = 9200;

    # The module maps each key here to /etc/opencloud/<key>.yaml
    settings = {
      app_registry = {
        driver = "static";
        static = {
          apps = [
            {
              id = "calendar";
              name = "Calendar";
              icon = "calendar";
              address = "https://opencloud.${baseDomain}/calendar/";
            }
            {
              id = "contacts";
              name = "Contacts";
              icon = "contacts";
              address = "https://opencloud.${baseDomain}/contacts/";
            }
            {
              id = "collabora";
              name = "Collabora Online";
              description = "Collabora Online integration";
              icon = "image-edit";
              address = "https://collabora.${baseDomain}";
              wopi_src = "https://collabora.${baseDomain}";
              extensions = [
                "odt"
                "ods"
                "odp"
                "doc"
                "docx"
                "xls"
                "xlsx"
                "ppt"
                "pptx"
                "pdf"
              ];
            }
          ];
        };
      };
      proxy = {
        additional_policies = [
          {
            name = "default";
            routes = [
              {
                endpoint = "/caldav/";
                backend = "http://127.0.0.1:5232";
                remote_user_header = "X-Remote-User";
                skip_x_access_token = true;
                additional_headers = [ { "X-Script-Name" = "/caldav"; } ];
              }
              {
                endpoint = "/.well-known/caldav";
                backend = "http://127.0.0.1:5232";
                remote_user_header = "X-Remote-User";
                skip_x_access_token = true;
                additional_headers = [ { "X-Script-Name" = "/caldav"; } ];
              }
              {
                endpoint = "/carddav/";
                backend = "http://127.0.0.1:5232";
                remote_user_header = "X-Remote-User";
                skip_x_access_token = true;
                additional_headers = [ { "X-Script-Name" = "/carddav"; } ];
              }
              {
                endpoint = "/.well-known/carddav";
                backend = "http://127.0.0.1:5232";
                remote_user_header = "X-Remote-User";
                skip_x_access_token = true;
                additional_headers = [ { "X-Script-Name" = "/carddav"; } ];
              }
            ];
          }
        ];
        role_quotas = {
          # 'd7beeea8-8ff4-406b-8fb6-ab2dd81e6b11' is the hardcoded ID for the 'User' role
          "d7beeea8-8ff4-406b-8fb6-ab2dd81e6b11" = 274877906944; # 256 GB in bytes
        };
        role_assignment = {
          driver = "oidc";
          oidc_role_mapper = {
            # This is the name of the 'key' in your Keycloak JWT
            role_claim = "opencloudRoles";
            role_mapping = [
              {
                role_name = "admin";
                claim_value = "admin"; # The value found in your Keycloak 'opencloudRoles' claim
              }
              {
                role_name = "admin";
                claim_value = "opencloud-admin";
              }
              {
                role_name = "user";
                claim_value = "opencloud-user";
              }
              # You can add more mappings here as needed
            ];
          };
        };
      };

      # This replaces your manual environment.etc."opencloud/csp.yaml"
      csp = {
        directives = {
          default-src = [ "'none'" ];
          child-src = [ "'self'" ];
          connect-src = [
            "'self'"
            "blob:"
            "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/"
            "https://update.opencloud.eu/"
            "https://sso.${baseDomain}"
            "https://opencloud-eu.github.io/"
            "https://collabora.${baseDomain}"
            "wss://collabora.${baseDomain}"
          ];
          font-src = [ "'self'" ];
          frame-ancestors = [
            "'self'"
            "https://opencloud.${baseDomain}"
            "https://collabora.${baseDomain}"
          ];
          frame-src = [
            "'self'"
            "data:"
            "blob:"
            "https://embed.diagrams.net/"
            "https://docs.opencloud.eu"
            "https://sso.${baseDomain}"
            "https://opencloud-eu.github.io/"
            "https://collabora.${baseDomain}" # <--- This allows the iframe to load
          ];
          img-src = [
            "'self'"
            "data:"
            "blob:"
            "https://tile.openstreetmap.org/"
            "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/"
            "https://sso.${baseDomain}"
          ];
          manifest-src = [ "'self'" ];
          media-src = [ "'self'" ];
          object-src = [
            "'self'"
          ];
          script-src = [
            "'self'"
            "data:"
            "blob:"
            "'unsafe-inline'"
            "'unsafe-hashes'"
            "'unsafe-eval'"
            "https://sso.${baseDomain}"
            "https://opencloud-eu.github.io/"
            "'unsafe-eval'"
          ];
          style-src = [
            "'self'"
            "'unsafe-inline'"
            "'unsafe-hashes'"
          ];
        };
      };
    };

    environment = {
      # Path is now managed by the module via the 'csp' key in settings
      PROXY_CSP_CONFIG_FILE_LOCATION = "/etc/opencloud/csp.yaml";

      # OIDC & General Config
      OC_URL = "https://opencloud.${baseDomain}";
      OC_OIDC_ISSUER = "https://${nodes.nix-keycloak.sub}.${baseDomain}/realms/${keycloakRealm}";
      EXTERNAL_OIDC_DOMAIN = "sso.${baseDomain}";
      PROXY_OIDC_REWRITE_WELLKNOWN = "true";
      OC_INSECURE = "true";
      OC_ADD_RUN_SERVICES = "collaboration,app-registry,gateway,calendar,contacts";
      CALENDAR_BACKEND_URL = "https://opencloud.${baseDomain}/caldav/";
      CONTACTS_BACKEND_URL = "https://opencloud.${baseDomain}/carddav/";
      PROXY_ENABLE_CALDAV = "true";
      PROXY_ENABLE_CARDDAV = "true";
      PROXY_OIDC_ACCESS_TOKEN_VERIFY_METHOD = "none";
      PROXY_AUTOPROVISION_ACCOUNTS = "true";
      OC_SHARING_PUBLIC_SHARE_MUST_HAVE_PASSWORD = "false";
      OC_SHARING_PUBLIC_WRITEABLE_SHARE_MUST_HAVE_PASSWORD = "false";
      PROXY_TLS = "false";
      PROXY_USER_OIDC_CLAIM = "sub";
      PROXY_USER_CS3_CLAIM = "username";
      PROXY_AUTOPROVISION_CLAIM_EMAIL = "email";
      PROXY_AUTOPROVISION_CLAIM_GROUPS = "groups";
      PROXY_ROLE_ASSIGNMENT_DRIVER = "oidc";
      PROXY_ROLE_ASSIGNMENT_OIDC_CLAIM = "groups";
      PROXY_AUTOPROVISION_CLAIM_USERNAME = "preferred_username";
      OC_EXCLUDE_RUN_SERVICES = "idp";
      WEB_OPTION_ACCOUNT_EDIT_LINK_HREF = "https://${nodes.nix-keycloak.sub}.${baseDomain}/realms/${keycloakRealm}/account";
      PROXY_AUTOPROVISION_CLAIM_DISPLAYNAME = "preferred_username";
      GRAPH_ASSIGN_DEFAULT_USER_ROLE = "false";
      GRAPH_USERNAME_MATCH = "none";
      GRAPH_LDAP_SERVER_WRITE_ENABLED = "true";
      OC_LOG_LEVEL = "info";
      COLLABORATION_APP_ADDR = "https://collabora.${baseDomain}";
      COLLABORATION_APP_PRODUCT = "Collabora";
      COLLABORATION_APP_INSECURE = "true";
      APP_REGISTRY_EXTERNAL_ADDR = "https://collabora.${baseDomain}";
      COLLABORATION_HTTP_INSECURE = "true";
      COLLABORATION_WOPI_SRC = "https://opencloud.${baseDomain}";

      COLLABORATION_APP_PROOF_DISABLE = "true";
    };
    environmentFile = config.sops.secrets."opencloud-env".path;
  };

  services.radicale = {
    enable = true;
    settings = {
      server = {
        hosts = [ "127.0.0.1:5232" ];
        ssl = false;
      };
      auth = {
        # Trust the header passed by the OpenCloud proxy
        type = "http_x_remote_user";
      };
      web.type = "none";
      storage = {
        filesystem_folder = "/var/lib/radicale/collections";
        # Pre-creating these makes them show up immediately in OpenCloud
        predefined_collections = builtins.toJSON {
          def-addressbook = {
            "D:displayname" = "OpenCloud Address Book";
            tag = "VADDRESSBOOK";
          };
          def-calendar = {
            "C:supported-calendar-component-set" = "VEVENT,VJOURNAL,VTODO";
            "D:displayname" = "OpenCloud Calendar";
            tag = "VCALENDAR";
          };
        };
      };
    };
  };

  networking.firewall.allowedTCPPorts = [
    9200
    9980
  ];
}
