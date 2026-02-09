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

  sops.secrets."dsp25-ssh" = {
    # This ensures the decrypted file is available for the autossh session
    path = "/etc/ssh/dsp25_ssh_config";
  };

  services.autossh.sessions = [
    {
      name = "dsp25-main-influx";
      user = "root"; # Ensure root has access to the sops secret path
      monitoringPort = 20000;
      # We point to the path defined in sops.secrets above
      extraArguments = "-N -T -F ${config.sops.secrets.dsp25-ssh.path} dsp25-main-influx";
    }
  ];

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
