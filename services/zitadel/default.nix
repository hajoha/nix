{ config, pkgs, ... }:

{
  services.zitadel = {
    enable = true;
    steps = {
      FirstInstance = {
        InstanceName = "ZITADEL";
        Org = {
          Name = "hackler";
          UserName = "admin";
        };
      };
    };

    settings = {
      log.level = "info";
      Port = 8081;
      ExternalDomain = "zitadel.johann-hackler.com";
      ExternalSecure = true;
      tlsMode = "disabled";
      TLS.Enabled = false;
      Cache = {
        AuthRequests = {
          Size = 100;
        };
      };
      Database = {
        # Postgres is the default database of ZITADEL
        postgres = {
          Host = "10.60.1.20"; # ZITADEL_DATABASE_POSTGRES_HOST
          Port = "5432"; # ZITADEL_DATABASE_POSTGRES_PORT
          Database = "zitadel"; # ZITADEL_DATABASE_POSTGRES_DATABASE
          MaxOpenConns = "25";
          MaxConnLifetime = "1h";
          MaxConnIdleTime = "5m";
          User = {
            Username = "zitadel"; # ZITADEL_DATABASE_POSTGRES_USER_USERNAME
            SSL.Mode = "disable";
          };

          admin = {
            existingDatabase = "postgres"; # ZITADEL_DATABASE_POSTGRES_ADMIN_EXISTINGDATABASE
            username = "admin"; # ZITADEL_DATABASE_POSTGRES_ADMIN_USERNAME
            Password = "/run/secrets/POSTGRES_ZITADEL_PASSWORD"; # mapped from secret
            ssl = {
              mode = "disable"; # ZITADEL_DATABASE_POSTGRES_ADMIN_SSL_MODE
              rootCert = ""; # ZITADEL_DATABASE_POSTGRES_ADMIN_SSL_ROOTCERT
              cert = ""; # ZITADEL_DATABASE_POSTGRES_ADMIN_SSL_CERT
              key = ""; # ZITADEL_DATABASE_POSTGRES_ADMIN_SSL_KEY
            };
          };
        };
      };
    };
    masterKeyFile = "/run/secrets/zitadel-creds/ZITADEL_MASTERKEY";
  };
  networking.nameservers = [ "10.60.1.16" ];
  networking.firewall.allowedTCPPorts = [
    8081
  ];
}
