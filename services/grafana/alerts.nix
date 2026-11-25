# Grafana alert rules on the Thanos datasource (folder "Homelab").
#
# Each rule is one PromQL query evaluated instantly; every series it returns
# above the threshold (default: > 0) is one alert instance. The queries
# return nothing or 0 when all is well, so "no data" counts as OK.
#
# Notifications: the default policy sends everything to ntfy on the VPS
# (contact point "ntfy" in ./default.nix).
{ lib, inventory }:
let
  running = lib.filterAttrs (_: n: n.service != null && n.autoStart) inventory.nodes;
  containerUnits = lib.concatMapStringsSep "|" (n: "container@${n}\\\\.service") (
    lib.attrNames running
  );

  # instances whose metrics must arrive
  agents = [
    "homelab"
    "hetzner-vps-01"
  ];

  rule =
    {
      uid,
      title,
      expr,
      summary,
      for ? "5m",
      severity ? "warning",
      threshold ? {
        type = "gt";
        params = [ 0 ];
      },
    }:
    {
      inherit uid title for;
      condition = "B";
      data = [
        {
          refId = "A";
          datasourceUid = "thanos";
          relativeTimeRange = {
            from = 600;
            to = 0;
          };
          model = {
            refId = "A";
            inherit expr;
            instant = true;
            range = false;
            intervalMs = 60000;
            maxDataPoints = 43200;
          };
        }
        {
          refId = "B";
          datasourceUid = "__expr__";
          model = {
            refId = "B";
            type = "threshold";
            expression = "A";
            conditions = [ { evaluator = threshold; } ];
          };
        }
      ];
      noDataState = "OK";
      execErrState = "Error";
      annotations.summary = summary;
      labels.severity = severity;
    };

  fsFilter = ''fstype!~"tmpfs|ramfs|squashfs|overlay"'';
in
{
  apiVersion = 1;
  groups = [
    {
      orgId = 1;
      name = "availability";
      folder = "Homelab";
      interval = "1m";
      rules = [
        (rule {
          uid = "probe-down";
          title = "Service unreachable";
          expr = "1 - probe_success";
          summary = "{{ $labels.probe }} ({{ $labels.instance }}) does not answer, probed from {{ $labels.prober }}";
          severity = "critical";
        })
        (rule {
          uid = "container-down";
          title = "Container not running";
          expr = ''1 - node_systemd_unit_state{instance="homelab", state="active", name=~"${containerUnits}"}'';
          summary = "{{ $labels.name }} is not active";
          severity = "critical";
          for = "3m";
        })
        (rule {
          uid = "unit-failed";
          title = "Failed systemd unit";
          expr = ''node_systemd_unit_state{state="failed"} == 1'';
          summary = "{{ $labels.name }} failed on {{ $labels.instance }}";
          for = "2m";
        })
        (rule {
          uid = "container-unit-failed";
          title = "Failed unit in a container";
          expr = "homelab_container_unit_failed";
          summary = "{{ $labels.unit }} failed in {{ $labels.machine }}";
          for = "2m";
        })
        (rule {
          uid = "agent-silent";
          title = "No metrics from a machine";
          expr = lib.concatMapStringsSep " or " (
            i: ''absent_over_time(node_uname_info{instance="${i}"}[10m])''
          ) agents;
          summary = "A machine stopped sending metrics (Alloy down or no route to nix-thanos)";
          for = "5m";
        })
        (rule {
          uid = "cert-expiry";
          title = "TLS certificate expires soon";
          expr = "(min by (instance) (probe_ssl_earliest_cert_expiry) - time()) / 86400";
          threshold = {
            type = "lt";
            params = [ 14 ];
          };
          summary = "{{ $labels.instance }}: certificate expires in {{ $values.A.Value | printf \"%.0f\" }} days";
          for = "1h";
        })
      ];
    }
    {
      orgId = 1;
      name = "resources";
      folder = "Homelab";
      interval = "1m";
      rules = [
        (rule {
          uid = "disk-full";
          title = "Filesystem almost full";
          expr = "100 * (1 - node_filesystem_avail_bytes{${fsFilter}} / node_filesystem_size_bytes{${fsFilter}}) > 90";
          summary = "{{ $labels.instance }} {{ $labels.mountpoint }} is {{ $values.A.Value | printf \"%.0f\" }}% full";
          for = "15m";
        })
        (rule {
          uid = "memory-high";
          title = "Memory almost exhausted";
          expr = "100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 90";
          summary = "{{ $labels.instance }} uses {{ $values.A.Value | printf \"%.0f\" }}% of its memory";
          for = "15m";
        })
        (rule {
          uid = "temperature-high";
          title = "Hardware too hot";
          expr = "max by (instance, chip, sensor) (node_hwmon_temp_celsius) > 85";
          summary = "{{ $labels.instance }} {{ $labels.chip }}/{{ $labels.sensor }} at {{ $values.A.Value }}°C";
          for = "10m";
          severity = "critical";
        })
        (rule {
          uid = "disk-temperature-high";
          title = "Disk too hot";
          expr = ''smartctl_device_temperature{temperature_type="current"} > 55'';
          summary = "{{ $labels.device }} at {{ $values.A.Value }}°C";
          for = "10m";
        })
        (rule {
          uid = "smart-failing";
          title = "SMART health check failed";
          expr = "1 - smartctl_device_smart_status";
          summary = "{{ $labels.device }} reports SMART failure";
          for = "0s";
          severity = "critical";
        })
        (rule {
          uid = "zpool-degraded";
          title = "ZFS pool not online";
          expr = ''1 - node_zfs_zpool_state{state="online"}'';
          summary = "pool {{ $labels.zpool }} is not ONLINE";
          for = "0s";
          severity = "critical";
        })
      ];
    }
  ];
}
