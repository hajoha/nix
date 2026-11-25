# Monitoring agent of the homelab: ONE Alloy, on the host, for the host and
# all containers (the containers run no agent of their own).
#
#   logs     the host journal + every container's journal, read from its
#            root (/var/lib/nixos-containers/<name>/var/log/journal)
#            -> nix-loki, labels instance=<host|container>, unit, level
#   metrics  host: CPU, memory, temperatures, disks, ZFS, systemd units
#            containers: CPU/memory/IO per container (cAdvisor on their
#            cgroups, label machine=<name>), failed units inside them
#            (textfile below), SMART of the disks
#            -> nix-thanos
#   probes   every container's primary port (tcp) and every nginx vhost
#            (https), label probe=<name>
#
# The host reaches nix-loki / nix-thanos through the router (management ->
# service VLAN), not over the macvlans.
{
  config,
  lib,
  pkgs,
  inventory,
  ...
}:
let
  inherit (config.homelab) nodes;
  inherit (lib) filterAttrs mapAttrs' nameValuePair;

  serviceNodes = filterAttrs (_: n: n.service != null) inventory.nodes;
  running = filterAttrs (_: n: n.autoStart) serviceNodes;

  ident = s: lib.replaceStrings [ "-" "." ] [ "_" "_" ] s;
  journalOf = name: "/var/lib/nixos-containers/${name}/var/log/journal";

  textfileDir = "/var/lib/homelab-metrics";

  vhosts = lib.filter (h: lib.hasSuffix ".${config.homelab.domain}" h && !lib.hasPrefix "*" h) (
    lib.attrNames config.containers.nix-nginx.config.services.nginx.virtualHosts
  );

  # Failed units inside each running container, for the node textfile
  # collector: homelab_container_unit_failed{machine,unit} 1
  containerUnits = pkgs.writeShellApplication {
    name = "homelab-container-units";
    runtimeInputs = with pkgs; [
      systemd
      coreutils
      gawk
    ];
    text = ''
      out=${textfileDir}/containers.prom
      tmp=$(mktemp -p ${textfileDir} .containers.XXXXXX)
      trap 'rm -f "$tmp"' EXIT
      {
        echo "# HELP homelab_container_unit_failed A unit inside a container is in the failed state."
        echo "# TYPE homelab_container_unit_failed gauge"
        echo "# HELP homelab_container_scrape_ok 1 if the container's units could be listed."
        echo "# TYPE homelab_container_scrape_ok gauge"
        for m in ${lib.concatStringsSep " " (lib.attrNames serviceNodes)}; do
          systemctl is-active --quiet "container@$m.service" || continue
          if units=$(systemctl -M "$m" list-units --state=failed --no-legend --plain 2>/dev/null); then
            echo "homelab_container_scrape_ok{machine=\"$m\"} 1"
            awk -v m="$m" 'NF { printf "homelab_container_unit_failed{machine=\"%s\",unit=\"%s\"} 1\n", m, $1 }' <<<"$units"
          else
            echo "homelab_container_scrape_ok{machine=\"$m\"} 0"
          fi
        done
      } > "$tmp"
      chmod 644 "$tmp"
      mv "$tmp" "$out"
    '';
  };
in
{
  imports = [ ../../modules/nixos/alloy-agent.nix ];

  homelab.alloy = {
    enable = true;
    instance = config.networking.hostName;
    lokiUrl = "http://${nodes.nix-loki.ip}:${toString nodes.nix-loki.port}/loki/api/v1/push";
    remoteWriteUrl = "http://${nodes.nix-thanos.ip}:19291/api/v1/receive";
    inherit textfileDir;

    probes =
      mapAttrs' (
        name: n:
        nameValuePair name {
          address = "${n.ip}:${toString n.port}";
          module = "tcp_connect";
        }
      ) (filterAttrs (_: n: n.port != 0) running)
      // lib.genAttrs vhosts (h: {
        address = "https://${h}";
        module = "http_up";
      })
      # ntfy on the VPS, where the alerts go (hosts/hetzner-vps-01/notify.nix)
      // {
        notify = {
          address = "https://notify.monitor.${config.homelab.domain}/v1/health";
          module = "http_up";
        };
      };
  };

  environment.etc."alloy/homelab.alloy".text = ''
    // --- container journals -------------------------------------------
    ${lib.concatMapStrings (name: ''

      loki.source.journal "${ident name}" {
        path          = "${journalOf name}"
        max_age       = "12h"
        relabel_rules = loki.relabel.journal.rules
        labels        = { job = "systemd-journal", instance = "${name}" }
        forward_to    = [loki.write.default.receiver]
      }
    '') (lib.attrNames serviceNodes)}

    // --- per-container resources (cgroups of container@<name>.service) --

    prometheus.exporter.cadvisor "machines" {
      docker_only                 = true
      raw_cgroup_prefix_allowlist = ["/machine.slice/"]
      enabled_metrics             = ["cpu", "memory", "diskIO"]
      storage_duration            = "2m"
    }

    prometheus.scrape "machines" {
      targets         = prometheus.exporter.cadvisor.machines.targets
      scrape_interval = "15s"
      forward_to      = [prometheus.relabel.machines.receiver]
    }

    prometheus.relabel "machines" {
      forward_to = [prometheus.remote_write.default.receiver]

      rule {
        source_labels = ["id"]
        regex         = "/machine\\.slice/container@(.+)\\.service"
        target_label  = "machine"
      }
      // only the container cgroups, not the ones below them
      rule {
        source_labels = ["machine"]
        regex         = ".+"
        action        = "keep"
      }
      rule {
        regex  = "id|name|image"
        action = "labeldrop"
      }
      rule {
        target_label = "job"
        replacement  = "cadvisor"
      }
      rule {
        target_label = "instance"
        replacement  = "${config.networking.hostName}"
      }
    }

    // --- SMART ---------------------------------------------------------

    prometheus.scrape "smartctl" {
      targets = [{
        "__address__" = "127.0.0.1:${toString config.services.prometheus.exporters.smartctl.port}",
        "job"         = "smartctl",
        "instance"    = "${config.networking.hostName}",
      }]
      scrape_interval = "60s"
      forward_to      = [prometheus.remote_write.default.receiver]
    }
  '';

  # Reads the container journals inside the container roots (0700) and the
  # cgroups / systemd of the host: root instead of the module's DynamicUser.
  systemd.services.alloy.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "root";
  };

  # Every container's journal directory exists, also before its first boot
  # (a missing path would fail the whole Alloy config). journald inside
  # stores persistently once the directory is there.
  systemd.tmpfiles.rules = [
    "d ${textfileDir} 0755 root root -"
  ]
  ++ map (name: "d ${journalOf name} 2755 root systemd-journal -") (lib.attrNames serviceNodes);

  services.prometheus.exporters.smartctl = {
    enable = true;
    listenAddress = "127.0.0.1";
    maxInterval = "5m";
  };

  systemd.services.homelab-container-units = {
    description = "Export failed units of the containers for Alloy";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe containerUnits;
    };
  };
  systemd.timers.homelab-container-units = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "1m";
    };
  };
}
