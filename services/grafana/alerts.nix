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

  # SMART raw counters that count damage (see dashboards.nix)
  sectorCounters = "5|196|197|198"; # reallocated / pending / uncorrectable sectors
  linkCounters = "187|188|199"; # reported uncorrectable, timeouts, CRC (cable)
  rawAttr = ids: ''smartctl_device_attribute{attribute_value_type="raw", attribute_id=~"${ids}"}'';
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
    {
      orgId = 1;
      name = "disks";
      folder = "Homelab";
      interval = "5m";
      # "worsens": counters that rose within the last day, normalized
      # values close to their threshold, NVMe wear and spare. A counter
      # that rose keeps the alert for 24h, then it clears by itself.
      rules = [
        (rule {
          uid = "smart-sectors-rising";
          title = "Disk is losing sectors";
          expr = "increase(${rawAttr sectorCounters}[1d]) > 0";
          summary = "{{ $labels.device }}: {{ $labels.attribute_name }} rose by {{ $values.A.Value | printf \"%.0f\" }} in 24h";
          for = "0s";
          severity = "critical";
        })
        (rule {
          uid = "smart-errors-rising";
          title = "Disk reports new errors";
          expr = "increase(${rawAttr linkCounters}[1d]) > 0";
          summary = "{{ $labels.device }}: {{ $labels.attribute_name }} rose by {{ $values.A.Value | printf \"%.0f\" }} in 24h (199 CRC: cable or connector)";
          for = "0s";
        })
        (rule {
          uid = "smart-near-threshold";
          title = "SMART value close to its failure threshold";
          expr = ''max by (device, attribute_name) (smartctl_device_attribute{attribute_value_type="value"}) - max by (device, attribute_name) (smartctl_device_attribute{attribute_value_type="thresh"} > 0)'';
          threshold = {
            type = "lt";
            params = [ 10 ];
          };
          summary = "{{ $labels.device }}: {{ $labels.attribute_name }} is {{ $values.A.Value }} above its threshold";
          for = "1h";
        })
        (rule {
          uid = "smart-selftest-failed";
          title = "SMART self-test failed";
          expr = "increase(smartctl_device_self_test_log_error_count[1d]) > 0";
          summary = "{{ $labels.device }}: a self-test failed in the last 24h";
          for = "0s";
          severity = "critical";
        })
        (rule {
          uid = "smart-errorlog-rising";
          title = "New entries in the disk error log";
          expr = "increase(smartctl_device_error_log_count[1d]) > 0";
          summary = "{{ $labels.device }}: {{ $values.A.Value | printf \"%.0f\" }} new error log entries in 24h";
          for = "0s";
        })
        (rule {
          uid = "nvme-media-errors";
          title = "NVMe media errors";
          expr = "increase(smartctl_device_media_errors[1d]) > 0";
          summary = "{{ $labels.device }}: {{ $values.A.Value | printf \"%.0f\" }} new media errors in 24h";
          for = "0s";
          severity = "critical";
        })
        (rule {
          uid = "nvme-critical-warning";
          title = "NVMe critical warning";
          expr = "smartctl_device_critical_warning";
          summary = "{{ $labels.device }} raises critical warning {{ $values.A.Value }}";
          for = "0s";
          severity = "critical";
        })
        (rule {
          uid = "nvme-wear";
          title = "NVMe almost worn out";
          expr = "smartctl_device_percentage_used > 80";
          summary = "{{ $labels.device }} has used {{ $values.A.Value }}% of its rated endurance";
          for = "1h";
        })
        (rule {
          uid = "nvme-spare-low";
          title = "NVMe spare blocks running out";
          expr = "smartctl_device_available_spare - on (device) smartctl_device_available_spare_threshold";
          threshold = {
            type = "lt";
            params = [ 10 ];
          };
          summary = "{{ $labels.device }}: spare only {{ $values.A.Value }} points above its threshold";
          for = "1h";
        })
        (rule {
          uid = "smart-not-read";
          title = "SMART values missing";
          expr = "absent_over_time(smartctl_device_smart_status[30m])";
          summary = "No SMART data for 30 minutes (smartctl exporter on the host down?)";
          for = "0s";
        })
      ];
    }
  ];
}
