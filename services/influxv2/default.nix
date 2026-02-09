{
  config,
  lib,
  pkgs,
  nodes,
  ...
}:

{
  # 1. SOPS Configuration
  sops.defaultSopsFile = ./secrets.enc.yaml;
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

    # InfluxDB settings
    settings = {
      # Bind to 0.0.0.0 on the container's eth0 (10.60.1.151)
      http-bind-address = "0.0.0.0:${toString nodes.nix-influx.port}";
      reporting-disabled = true;
    };

    provision = {
      enable = true;
      initialSetup = {
        organization = "home";
        bucket = "debug";
        username = "admin";
        # Managed via sops-nix
        passwordFile = config.sops.secrets."INFLUX_ADMIN_PASSWORD".path;
        tokenFile = config.sops.secrets."INFLUX_ADMIN_TOKEN".path;
      };
    };
  };

  # Port management is now handled by mkLXC and network.nix
  system.stateVersion = "25.11";
}
