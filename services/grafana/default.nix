{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Tell sops-nix which secrets to make available
  sops.secrets = {
    "GRAFANA_ADMIN_PASSWORD" = {
      owner = "grafana";
    };
  };

  services.grafana = {
    enable = true;
    provision = {
      enable = true;

      datasources.settings.datasources = [
        # Provisioning a built-in data source
        {
          name = "influxdbv2";
          type = "influxdbv2";
          url = "http://10.60.1.26:8086";
          isDefault = true;
          editable = false;
        }

      ];

    };
    settings = {
      server = {
        http_addr = "0.0.0.0";
        http_port = 3000;
        enforce_domain = false;
        enable_gzip = true;
        domain = "grafana.johann-hackler.com";
        root_url = "https://grafana.johann-hackler.com";

      };
      security.admin_password = "$__file{${config.sops.secrets."GRAFANA_ADMIN_PASSWORD".path}}";

      analytics.reporting_enabled = false;
    };
  };
}
