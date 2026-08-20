{
  config,
  lib,
  pkgs,
  inputs,
  nodes,
  baseDomain,
  ...
}:
let
  node = nodes.nix-sparkyfitness;
  domain = "${node.sub}.${baseDomain}"; # fitness.johann-hackler.com
in
{
  imports = [ inputs.sparkyfitness.nixosModules.sparkyfitness ];

  # Bundle of secrets consumed as a systemd EnvironmentFile by the backend unit.
  # Must contain SPARKY_FITNESS_DB_PASSWORD, SPARKY_FITNESS_APP_DB_PASSWORD,
  # SPARKY_FITNESS_API_ENCRYPTION_KEY, BETTER_AUTH_SECRET.
  sops.secrets."sparkyfitness-env" = {
    format = "yaml";
    sopsFile = ./secrets.enc.yaml;
    mode = "0400";
    restartUnits = [ "sparkyfitness-server.service" ];
  };

  # Same file nix-postgres decrypts (via servicesWithDB) — encrypted to both
  # host keys in .sops.yaml. Only used here to keep the values in sync visually;
  # it isn't read directly by this module (see note below).
  sops.secrets."sparkyfitness-postgres-password" = {
    format = "yaml";
    sopsFile = ./postgres.enc.yaml;
    key = "password";
    mode = "0400";
  };

  services.sparkyfitness = {
    enable = true;
    frontendUrl = "https://${domain}";
    environmentFile = config.sops.secrets."sparkyfitness-env".path;
    port = 3010;

    database = {
      createLocally = false;
      host = nodes.nix-postgres.ip; # 10.60.1.20
      port = nodes.nix-postgres.port; # 5432
      name = "sparkyfitness";
      user = "sparkyfitness";
    };

    nginx = {
      enable = true;
      virtualHost = domain;
    };

    # garmin.enable = true; # optional, no extra secrets needed
  };
}
