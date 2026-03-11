{ config, nodes, lib, ... }:

{
  # 1. User and Persistence Setup
  users.users.loki = {
    group = "loki";
    isSystemUser = true;
    home = "/var/lib/loki";
  };
  users.groups.loki = { };

  # 2. Loki Service Configuration
  services.loki = {
    enable = true;
    configuration = {
      auth_enabled = false; # Internal network trust

      server = {
        http_listen_address = nodes.nix-loki.ip;
        http_listen_port = 3100;
        grpc_listen_port = 9096;
      };

      common = {
        instance_addr = nodes.nix-loki.ip;
        path_prefix = "/var/lib/loki";
        storage.filesystem = {
          chunks_directory = "/var/lib/loki/chunks";
          rules_directory = "/var/lib/loki/rules";
        };
        replication_factor = 1;
        ring.kvstore.store = "inmemory";
      };

      query_range = {
        results_cache.cache.embedded_cache = {
          enabled = true;
          max_size_mb = 100;
        };
      };

      schema_config.configs = [{
        from = "2024-01-01";
        store = "tsdb";
        object_store = "filesystem";
        schema = "v13";
        index = {
          prefix = "index_";
          period = "24h";
        };
      }];

      limits_config = {
        reject_old_samples = true;
        reject_old_samples_max_age = "672h"; # 28 days of log retention
        allow_structured_metadata = true;
        # Limits to prevent a single spammy LXC from crashing Loki
        ingestion_rate_mb = 10;
        ingestion_burst_size_mb = 20;
      };
    };
  };

  # 3. Systemd & LXC Compatibility
  # We disable the typical systemd hardening that breaks in unprivileged LXC
  systemd.services.loki = {
    preStart = "mkdir -p /var/lib/loki && chown loki:loki /var/lib/loki";
    serviceConfig = {
      PrivateTmp = lib.mkForce false;
      ProtectSystem = "full";
      ProtectHome = lib.mkForce "read-only";
      # Ensure Loki can write its indices and chunks
      ReadWritePaths = [ "/var/lib/loki" ];
      # standard NixOS state management
      StateDirectory = "loki";
      StateDirectoryMode = "0700";
    };
  };

  # 4. Networking
  # Open 3100 for Alloy clients and Grafana
  networking.firewall.allowedTCPPorts = [ 3100 ];

  system.stateVersion = "25.11";
}