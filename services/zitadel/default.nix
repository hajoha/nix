{
  config,
  pkgs,
  nodes,
  baseDomain,
  ...
}:

{
  # 1. SOPS Configuration
  sops.defaultSopsFile = ./secrets.enc.yaml;
  sops.secrets = {
    "zitadel/masterkey" = {
      owner = "zitadel";
    };
    "zitadel/env" = {
      owner = "zitadel";
      restartUnits = [ "zitadel.service" ];
    };
    "zitadel/postgres_admin_password" = {
      owner = "zitadel";
    };
    "zitadel/POSTGRES_ZITADEL_PASSWORD" = {
      owner = "zitadel";
    };
  };

  services.zitadel = {
    enable = true;

    # Path to the decrypted masterkey
    masterKeyFile = config.sops.secrets."zitadel/masterkey".path;

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
      Port = nodes.nix-zitadel.port; # 8081
      # Must use FQDN for browser redirects and cookie safety
      ExternalDomain = "${nodes.nix-zitadel.hostname}.${baseDomain}";
      ExternalSecure = true;

      # TLS is terminated at the nix-nginx gateway
      tlsMode = "disabled";
      TLS.Enabled = false;

      Database = {
        postgres = {
          # Connect to the central nix-postgres node
          Host = nodes.nix-postgres.ip;
          Port = nodes.nix-postgres.port;
          Database = "zitadel";

          User = {
            Username = "zitadel";
            SSL.Mode = "disable";
          };

          admin = {
            existingDatabase = "postgres";
            username = "admin";
            # Path to the admin password secret
            Password = "/run/secrets/zitadel/POSTGRES_ZITADEL_PASSWORD";
            ssl.mode = "disable";
          };
        };
      };
    };
  };

  # DNS: Use your internal AdGuard instance for resolution
  systemd.services.zitadel.serviceConfig.EnvironmentFile = config.sops.secrets."zitadel/env".path;

  # State version for the container
  system.stateVersion = "25.11";
}
