# Grafana Alloy as the one monitoring agent of a machine: its journal to
# Loki, node metrics (CPU, memory, disks, temperatures, ZFS, systemd units)
# and optional blackbox probes to Thanos (remote write).
#
# Samples and log lines keep the time they were taken; when the receiver is
# unreachable, Alloy buffers metrics in its WAL (up to 8h) and the journal
# position, and sends the backlog later.
#
# More components (extra journals, scrapes) go into further files under
# /etc/alloy/*.alloy; Alloy loads the whole directory as one config and they
# can use `loki.write.default`, `loki.relabel.journal` and
# `prometheus.remote_write.default` defined here.
#
#   http://127.0.0.1:12345    pipeline UI (ssh -L 12345:127.0.0.1:12345 …)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.homelab.alloy;

  blackboxConfig = pkgs.writeText "blackbox.yml" (
    builtins.toJSON {
      modules = {
        tcp_connect = {
          prober = "tcp";
          timeout = "5s";
          tcp.preferred_ip_protocol = "ip4";
        };
        # "the service answers": any non-5xx. Logins (401/403) and
        # redirects to the SSO count as up; 502/503/504 from nginx do not.
        http_up = {
          prober = "http";
          timeout = "10s";
          http = {
            preferred_ip_protocol = "ip4";
            follow_redirects = false;
            valid_status_codes = [
              200
              201
              204
              301
              302
              303
              307
              308
              400
              401
              403
              404
              405
            ];
          };
        };
      };
    }
  );

  probeTargets = lib.concatStrings (
    lib.mapAttrsToList (name: p: ''
      target {
        name    = "${name}"
        address = "${p.address}"
        module  = "${p.module}"
      }
    '') cfg.probes
  );
in
{
  options.homelab.alloy = {
    enable = lib.mkEnableOption "the Alloy monitoring agent";

    instance = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "`instance` label of this machine's logs and metrics.";
    };

    lokiUrl = mkOption {
      type = types.str;
      description = "Loki push endpoint.";
    };

    remoteWriteUrl = mkOption {
      type = types.str;
      description = "Prometheus remote write endpoint (Thanos Receive).";
    };

    textfileDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Directory of *.prom files exported by the node collector.";
    };

    probes = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            address = mkOption {
              type = types.str;
              description = "host:port for tcp_connect, a URL for http_up.";
            };
            module = mkOption {
              type = types.enum [
                "tcp_connect"
                "http_up"
              ];
            };
          };
        }
      );
      default = { };
      description = "Blackbox probes run from this machine, by name.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.alloy.enable = true; # loads /etc/alloy/*.alloy

    environment.etc."alloy/base.alloy".text = ''
      logging {
        level  = "warn"
        format = "logfmt"
      }

      // --- logs ---------------------------------------------------------

      loki.write "default" {
        endpoint {
          url = "${cfg.lokiUrl}"
        }
      }

      // shared by every journal source
      loki.relabel "journal" {
        forward_to = []

        rule {
          source_labels = ["__journal__systemd_unit"]
          target_label  = "unit"
        }
        rule {
          source_labels = ["__journal_priority_keyword"]
          target_label  = "level"
        }
      }

      // this machine's own journal (local machine id only)
      loki.source.journal "local" {
        max_age       = "12h"
        relabel_rules = loki.relabel.journal.rules
        labels        = { job = "systemd-journal", instance = "${cfg.instance}" }
        forward_to    = [loki.write.default.receiver]
      }

      // --- metrics ------------------------------------------------------

      prometheus.remote_write "default" {
        endpoint {
          url = "${cfg.remoteWriteUrl}"
        }
        wal {
          max_keepalive_time = "8h"
        }
      }

      prometheus.exporter.unix "node" {
        enable_collectors = ["systemd"]

        filesystem {
          fs_types_exclude     = "^(autofs|binfmt_misc|bpf|cgroup2?|configfs|debugfs|devpts|devtmpfs|efivarfs|fusectl|hugetlbfs|mqueue|nsfs|overlay|proc|pstore|ramfs|rpc_pipefs|securityfs|squashfs|sysfs|tmpfs|tracefs)$"
          mount_points_exclude = "^/(dev|proc|run|sys|nix/store)($|/)"
        }

        systemd {
          unit_include = ".+\\.(service|timer|mount)"
        }
      ${lib.optionalString (cfg.textfileDir != null) ''

        textfile {
          directory = "${cfg.textfileDir}"
        }
      ''}
      }

      discovery.relabel "node" {
        targets = prometheus.exporter.unix.node.targets

        rule {
          target_label = "job"
          replacement  = "node"
        }
        rule {
          target_label = "instance"
          replacement  = "${cfg.instance}"
        }
      }

      prometheus.scrape "node" {
        targets         = discovery.relabel.node.output
        scrape_interval = "15s"
        forward_to      = [prometheus.remote_write.default.receiver]
      }
      ${lib.optionalString (cfg.probes != { }) ''

        // --- probes -------------------------------------------------------

        prometheus.exporter.blackbox "probes" {
          config_file = "${blackboxConfig}"

        ${probeTargets}
        }

        discovery.relabel "probes" {
          targets = prometheus.exporter.blackbox.probes.targets

          // job is "integrations/blackbox/<name>"
          rule {
            source_labels = ["job"]
            regex         = "integrations/blackbox/(.+)"
            target_label  = "probe"
          }
          rule {
            source_labels = ["__param_module"]
            target_label  = "module"
          }
          rule {
            source_labels = ["__param_target"]
            target_label  = "instance"
          }
          rule {
            target_label = "prober"
            replacement  = "${cfg.instance}"
          }
          rule {
            target_label = "job"
            replacement  = "blackbox"
          }
        }

        prometheus.scrape "probes" {
          targets         = discovery.relabel.probes.output
          scrape_interval = "30s"
          scrape_timeout  = "15s"
          forward_to      = [prometheus.remote_write.default.receiver]
        }
      ''}
    '';

    # Not opened in the firewall: the UI stays on 127.0.0.1:12345.
  };
}
