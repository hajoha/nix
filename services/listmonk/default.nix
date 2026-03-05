{ config, pkgs, nodes, baseDomain, ... }:

{
  
  sops.secrets."listmonk-env" = {
    format = "yaml";
    sopsFile = ./secrets.enc.yaml;
    # This makes the secret readable by the listmonk user/group
    owner = "listmonk"; 
  };
  services.listmonk = {
    enable = true;
    
    # Static settings (config.toml)
    settings = {
      app.address = "0.0.0.0:9000";
      db = {
        host = nodes.nix-postgres.ip;
        port = nodes.nix-postgres.port;
        user = "listmonk";
        database = "listmonk";
        # Password should be in secretFile as LISTMONK_db__password
      };
    };

    # This file should contain your OIDC secrets and DB password
    secretFile = config.sops.secrets."listmonk-env".path;

    # Dynamic settings (Stored in Postgres)
    database.settings = {
      "auth.enabled" = true;
      "auth.method" = "oidc";
    };
  };
}