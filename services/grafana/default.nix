{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (config.homelab) nodes sso;
in
{
  sops.defaultSopsFile = ./secrets.enc.yaml;
  # 1. SOPS Secrets
  sops.secrets = {
    "GRAFANA_ADMIN_PASSWORD" = {
      owner = "grafana";
    };
    "GRAFANA_SECRET_KEY" = {
      owner = "grafana";
    };
    "GRAFANA_KEYCLOAK_SECRET" = {
      owner = "grafana";
    };
    "dsp25-ssh" = {
      path = "/etc/ssh/dsp25_ssh_config";
    };
  };

  # 2. SSH Tunnel for Remote InfluxDB
  services.autossh.sessions = [
    {
      name = "dsp25-main-influx";
      user = "root";
      monitoringPort = 20000;
      extraArguments = "-N -T -F ${config.sops.secrets.dsp25-ssh.path} dsp25-main-influx";
    }
  ];

  # 3. Grafana Service
  services.grafana = {
    enable = true;

    provision = {
      enable = true;
      datasources.settings = {
        datasources = [
          # Metrics: Thanos Query (raw 15d, 5m 90d, 1h 5y; picks the
          # resolution from the graph's step)
          {
            name = "Thanos";
            uid = "thanos";
            type = "prometheus";
            url = nodes.nix-thanos.addr;
            access = "proxy";
            isDefault = true;
            jsonData = {
              prometheusType = "Thanos";
              timeInterval = "15s"; # Alloy's scrape interval
              httpMethod = "POST";
            };
          }
          # Logs: dedicated Loki host
          {
            name = "Loki";
            uid = "loki";
            type = "loki";
            url = "http://${nodes.nix-loki.ip}:3100";
            access = "proxy"; # Grafana fetches logs on behalf of the user
            jsonData.maxLines = 1000;
          }
        ];
        # nix-influx is retired
        deleteDatasources = [
          {
            name = "InfluxDB_v2";
            orgId = 1;
          }
        ];
      };

      dashboards.settings.providers = [
        {
          name = "homelab";
          folder = "Homelab";
          type = "file";
          allowUiUpdates = false;
          options.path = import ./dashboards.nix { inherit pkgs lib; };
        }
      ];

      alerting.rules.settings = import ./alerts.nix {
        inherit lib;
        inventory = import ../../inventory { inherit lib; };
      };
    };

    settings = {
      server = {
        http_addr = "0.0.0.0";
        http_port = nodes.nix-grafana.port;
        domain = nodes.nix-grafana.hostname;
        root_url = "${nodes.nix-grafana.url}/";
        enforce_domain = false;
        enable_gzip = true;
      };

      # --- Keycloak OIDC Integration ---
      "auth.generic_oauth" = {
        enabled = true;
        name = "SSO";
        allow_sign_up = true;
        client_id = "grafana-oauth";
        client_secret = "$__file{${config.sops.secrets."GRAFANA_KEYCLOAK_SECRET".path}}";
        scopes = "openid profile email groups";
        # Endpoints mapped to your Keycloak instance
        auth_url = "${sso.issuer}/protocol/openid-connect/auth";
        token_url = "${sso.issuer}/protocol/openid-connect/token";
        api_url = "${sso.issuer}/protocol/openid-connect/userinfo";

        # RBAC: Map Keycloak groups to Grafana roles
        role_attribute_path = "contains(groups, 'grafana-admin') && 'Admin' || contains(groups, 'grafana-editor') && 'Editor' || 'Viewer'";
        login_attribute_path = "preferred_username";
        email_attribute_path = "email";
        name_attribute_path = "preferred_username";

      };

      security = {
        secret_key = "$__file{${config.sops.secrets."GRAFANA_SECRET_KEY".path}}";
        admin_password = "$__file{${config.sops.secrets."GRAFANA_ADMIN_PASSWORD".path}}";
        allow_embedding = true;
      };

      analytics.reporting_enabled = false;
    };
  };

  system.stateVersion = "25.11";
}
