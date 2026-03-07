{ config, nodes, ... }:

{
  services.grafana-alloy = {
    enable = true;
    # Alloy uses the "River" configuration format
    settings = ''
      logging {
        level  = "info"
        format = "logfmt"
      }

      // 1. Collect logs from the local systemd journal
      loki.source.journal "read_journal" {
        forward_to    = [loki.write.remote_loki.receiver]
        relabel_rules = loki.relabel.journal_metadata.rules
      }

      // 2. Add labels so we know which LXC sent the logs
      loki.relabel "journal_metadata" {
        rule {
          source_labels = ["__journal__systemd_unit"]
          target_label  = "unit"
        }
        rule {
          replacement  = "${config.networking.hostName}"
          target_label = "instance"
        }
      }

      // 3. Send the logs to your dedicated Loki host
      loki.write "remote_loki" {
        endpoint {
          url = "http://${nodes.nix-loki.ip}:3100/loki/api/v1/push"
        }
      }
    '';
  };

  # Give Alloy permission to read the system journal
  users.users.alloy.extraGroups = [ "systemd-journal" ];

  # Standard port for Alloy's internal dashboard (useful for debugging)
  networking.firewall.allowedTCPPorts = [ 12345 ];
}