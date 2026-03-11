{ config, lib, pkgs, nodes, baseDomain, keycloakRealm, ... }:

let
  # Build the Keycloak URL dynamically from your nodes map
  keycloakUrl = "https://${nodes.nix-keycloak.sub}.${baseDomain}";
in
{
  sops.defaultSopsFile = ./secrets.enc.yaml;
  # 1. SOPS Secrets
  sops.secrets = {
    "GRAFANA_ADMIN_PASSWORD" = { owner = "grafana"; };
    "GRAFANA_SECRET_KEY" = { owner = "grafana"; };
    "GRAFANA_KEYCLOAK_SECRET" = { owner = "grafana"; };
    "dsp25-ssh" = { path = "/etc/ssh/dsp25_ssh_config"; };
  };

  # 2. SSH Tunnel for Remote InfluxDB
  services.autossh.sessions = [{
    name = "dsp25-main-influx";
    user = "root";
    monitoringPort = 20000;
    extraArguments = "-N -T -F ${config.sops.secrets.dsp25-ssh.path} dsp25-main-influx";
  }];

  # 3. Grafana Service
  services.grafana = {
    enable = true;

    provision = {
      enable = true;
      datasources.settings.datasources = [
        # Remote InfluxDB (via SSH Tunnel)
        {
          name = "InfluxDB_v2";
          type = "influxdb";
          url = "http://${nodes.nix-influx.ip}:${toString nodes.nix-influx.port}";
          isDefault = true;
          jsonData = {
            version = "Flux";
            organization = "main";
            defaultBucket = "default";
            tlsSkipVerify = true;
          };
        }
        # Dedicated Loki Host
        {
          name = "Loki";
          type = "loki";
          url = "http://${nodes.nix-loki.ip}:3100";
          access = "proxy"; # Important: Grafana fetches logs on behalf of the user
        }
      ];
    };

    settings = {
      server = {
        http_addr = "0.0.0.0";
        http_port = nodes.nix-grafana.port;
        domain = nodes.nix-grafana.hostname;
        root_url = "https://${nodes.nix-grafana.hostname}.${baseDomain}/";
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
        auth_url = "${keycloakUrl}/realms/${keycloakRealm}/protocol/openid-connect/auth";
        token_url = "${keycloakUrl}/realms/${keycloakRealm}/protocol/openid-connect/token";
        api_url = "${keycloakUrl}/realms/${keycloakRealm}/protocol/openid-connect/userinfo";
        
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