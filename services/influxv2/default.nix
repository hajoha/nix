{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Tell sops-nix which secrets to make available
  sops.secrets = {
    "INFLUX_ADMIN_PASSWORD" = {
      owner = "influxdb2";
    };
    "INFLUX_ADMIN_TOKEN" = {
      owner = "influxdb2";
    };
  };

  services.influxdb2 = {
    enable = true;
    settings = {
    };
    provision = {
      enable = true;
      initialSetup = {
        organization = "home";
        bucket = "debug";
        username = "admin";
        passwordFile = config.sops.secrets."INFLUX_ADMIN_PASSWORD".path;
        tokenFile = config.sops.secrets."INFLUX_ADMIN_TOKEN".path;
      };
    };
  };

}
