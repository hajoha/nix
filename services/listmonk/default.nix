{
  config,
  pkgs,
  nodes,
  baseDomain,
  ...
}:

{

  users.users.listmonk = {
    isSystemUser = true;
    group = "listmonk";
  };
  users.groups.listmonk = { };

  # Update your sops config to ensure the group matches
  sops.secrets."listmonk-env" = {
    sopsFile = ./secrets.enc.yaml;
    owner = "listmonk";
    group = "listmonk";
    mode = "0440";
  };

  sops.secrets."env" = {
    sopsFile = ./postgres.enc.yaml;
    owner = "listmonk";
    group = "listmonk";
    mode = "0440";
    key = "password";
  };

  sops.templates.".env" = {
    owner = "listmonk";

    content = ''
      ${config.sops.placeholder."listmonk-env"}
      LISTMONK_db__password=${config.sops.placeholder."env"}
    '';
  };

  services.listmonk.database.mutableSettings = true;
  services.listmonk = {
    enable = true;

    # Static settings (config.toml)
    settings = {
      app.address = "0.0.0.0:9000";
      app.root_url = "https://${nodes.nix-listmonk.sub}.${baseDomain}";
      db = {
        host = nodes.nix-postgres.ip;
        port = nodes.nix-postgres.port;
        user = "listmonk";
        database = "listmonk";
        ssl_mode = "disable";
        # Password should be in secretFile as LISTMONK_db__password
      };
    };

    secretFile = config.sops.templates.".env".path;

    database.settings = {
      "auth.enabled" = true;
      "auth.method" = "oidc";
      smtp = [
      ];
    };
  };

  systemd.services.listmonk.serviceConfig.Environment = [
    "PGHOST=${nodes.nix-postgres.ip}"
    "PGPORT=${toString nodes.nix-postgres.port}"
    "PGUSER=listmonk"
    "PGDATABASE=listmonk"
  ];
}
