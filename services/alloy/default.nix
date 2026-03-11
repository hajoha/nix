{ config, nodes, ... }:

{
  # 1. Enable the service using your specific NixOS module
  services.alloy = {
    enable = true;
    configPath = "/etc/alloy/config.alloy";
  };

  # 2. Define the configuration file
  environment.etc."alloy/config.alloy".text = ''
    logging {
      level  = "info"
      format = "logfmt"
    }

    // --- LOG PIPELINE ---

    // Step 1: Read from the local systemd journal
    loki.source.journal "read_journal" {
      // Forward logs to the relabeling component
      forward_to = [loki.relabel.journal_metadata.receiver]
    }

    // Step 2: Add metadata (LXC Hostname and Service Unit)
    loki.relabel "journal_metadata" {
      // Forward processed logs to the Loki write component
      forward_to = [loki.write.remote_loki.receiver]

      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
      }
      rule {
        replacement  = constants.hostname
        target_label = "instance"
      }
    }

    // Step 3: Send the logs to the central Loki server
    loki.write "remote_loki" {
      endpoint {
        url = "http://${nodes.nix-loki.ip}:3100/loki/api/v1/push"
      }
    }
  '';

  # 3. Networking
  # Open the default Alloy UI port for debugging the pipeline graph
  networking.firewall.allowedTCPPorts = [ 12345 ];
}