{
  config,
  lib,
  pkgs,
  nodes,
  baseDomain,
  ...
}:

{
  # 1. SOPS Configuration
  sops.defaultSopsFile = ./secrets.enc.yaml;
  sops.secrets."GRAFANA_ADMIN_PASSWORD" = {
    owner = "grafana";
  };

  services.grafana = {
    enable = true;

    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "InfluxDB_v2";
          type = "influxdb";
          # Referenced from the central network.nix map
          url = "http://${nodes.nix-influx.ip}:${toString nodes.nix-influx.port}";
          isDefault = true;
          editable = false;
          jsonData = {
            version = "Flux";
            organization = "main";
            defaultBucket = "default";
            tlsSkipVerify = true;
          };
        }
      ];
    };

    settings = {
      server = {
        # Bind to 0.0.0.0 for the container eth0 interface
        http_addr = "0.0.0.0";
        http_port = nodes.nix-grafana.port;

        # Use the node names as hostnames without baseDomain (as requested)
        domain = nodes.nix-grafana.hostname;
        root_url = "https://${nodes.nix-grafana.hostname}.${baseDomain}/";

        enforce_domain = false;
        enable_gzip = true;
      };

      security = {
        # Securely read password via sops-nix file path
        admin_password = "$__file{${config.sops.secrets."GRAFANA_ADMIN_PASSWORD".path}}";
        allow_embedding = true;
      };

      analytics.reporting_enabled = false;
    };
  };

  # Port opening is now handled by the mkLXC generator merging network.nix
  system.stateVersion = "25.11";
}
