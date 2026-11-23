# Provisioned dashboards (folder "Homelab", read-only in the UI; copy one
# to edit it):
#
#   homelab.json     overview: probes, containers, host, logs
#   node-full.json   "Node Exporter Full" (grafana.com 1860), per machine
{ pkgs, lib }:
let
  prom = {
    type = "prometheus";
    uid = "thanos";
  };
  loki = {
    type = "loki";
    uid = "loki";
  };

  q = expr: legend: {
    datasource = prom;
    inherit expr;
    legendFormat = legend;
    refId = "A";
  };

  panel =
    {
      title,
      type ? "timeseries",
      x,
      y,
      w ? 12,
      h ? 8,
      targets,
      unit ? null,
      extra ? { },
    }:
    lib.recursiveUpdate {
      inherit title type targets;
      datasource = prom;
      gridPos = { inherit x y w h; };
      fieldConfig = {
        defaults = lib.optionalAttrs (unit != null) { inherit unit; };
        overrides = [ ];
      };
      options = { };
    } extra;

  stat =
    args:
    panel (
      args
      // {
        type = "stat";
        h = 4;
        w = 4;
        extra = lib.recursiveUpdate {
          options = {
            reduceOptions.calcs = [ "lastNotNull" ];
            colorMode = "background";
            graphMode = "none";
          };
        } (args.extra or { });
      }
    );

  thresholds = steps: {
    fieldConfig.defaults.thresholds = {
      mode = "absolute";
      steps = map (s: {
        color = s.c;
        value = s.v;
      }) steps;
    };
  };

  okIfZero = thresholds [
    {
      c = "green";
      v = null;
    }
    {
      c = "red";
      v = 1;
    }
  ];

  homelab = {
    uid = "homelab";
    title = "Homelab";
    tags = [ "homelab" ];
    timezone = "browser";
    schemaVersion = 39;
    refresh = "1m";
    time = {
      from = "now-24h";
      to = "now";
    };
    panels = lib.imap1 (i: p: p // { id = i; }) [
      (stat {
        title = "Services down";
        x = 0;
        y = 0;
        targets = [ (q "count(probe_success == 0) or vector(0)" "") ];
        extra = okIfZero;
      })
      (stat {
        title = "Containers running";
        x = 4;
        y = 0;
        targets = [
          (q ''sum(node_systemd_unit_state{instance="homelab", name=~"container@.+", state="active"})'' "")
        ];
      })
      (stat {
        title = "Failed units";
        x = 8;
        y = 0;
        targets = [
          (q ''(count(node_systemd_unit_state{state="failed"} == 1) or vector(0)) + (count(homelab_container_unit_failed) or vector(0))'' "")
        ];
        extra = okIfZero;
      })
      (stat {
        title = "Hottest sensor";
        x = 12;
        y = 0;
        unit = "celsius";
        targets = [ (q ''max(node_hwmon_temp_celsius{instance="homelab"})'' "") ];
        extra = thresholds [
          {
            c = "green";
            v = null;
          }
          {
            c = "orange";
            v = 70;
          }
          {
            c = "red";
            v = 85;
          }
        ];
      })
      (stat {
        title = "Fullest filesystem";
        x = 16;
        y = 0;
        unit = "percent";
        targets = [
          (q ''max(100 * (1 - node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs|squashfs|overlay"} / node_filesystem_size_bytes{fstype!~"tmpfs|ramfs|squashfs|overlay"}))'' "")
        ];
        extra = thresholds [
          {
            c = "green";
            v = null;
          }
          {
            c = "orange";
            v = 80;
          }
          {
            c = "red";
            v = 90;
          }
        ];
      })
      (stat {
        title = "Uptime (host)";
        x = 20;
        y = 0;
        unit = "s";
        targets = [ (q ''time() - node_boot_time_seconds{instance="homelab"}'' "") ];
        extra = thresholds [
          {
            c = "blue";
            v = null;
          }
        ];
      })

      (panel {
        title = "Probes";
        type = "state-timeline";
        x = 0;
        y = 4;
        w = 24;
        h = 12;
        targets = [ (q "probe_success" "{{probe}} ({{prober}})") ];
        extra = {
          fieldConfig.defaults = {
            mappings = [
              {
                type = "value";
                options = {
                  "0" = {
                    text = "down";
                    color = "red";
                  };
                  "1" = {
                    text = "up";
                    color = "green";
                  };
                };
              }
            ];
            color.mode = "thresholds";
          };
          options = {
            showValue = "never";
            mergeValues = true;
          };
        };
      })

      (panel {
        title = "CPU";
        x = 0;
        y = 16;
        unit = "percent";
        targets = [
          (q ''100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[$__rate_interval])))'' "{{instance}}")
        ];
      })
      (panel {
        title = "Memory used";
        x = 12;
        y = 16;
        unit = "percent";
        targets = [
          (q "100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)" "{{instance}}")
        ];
      })
      (panel {
        title = "Temperatures";
        x = 0;
        y = 24;
        unit = "celsius";
        targets = [
          (q ''node_hwmon_temp_celsius{instance="homelab"}'' "{{chip}} {{sensor}}")
          ((q ''smartctl_device_temperature{temperature_type="current"}'' "disk {{device}}") // { refId = "B"; })
        ];
      })
      (panel {
        title = "Filesystems used";
        type = "bargauge";
        x = 12;
        y = 24;
        unit = "percent";
        targets = [
          (
            (q ''100 * (1 - node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs|squashfs|overlay"} / node_filesystem_size_bytes{fstype!~"tmpfs|ramfs|squashfs|overlay"})'' "{{instance}} {{mountpoint}}")
            // {
              instant = true;
            }
          )
        ];
        extra = lib.recursiveUpdate (thresholds [
          {
            c = "green";
            v = null;
          }
          {
            c = "orange";
            v = 80;
          }
          {
            c = "red";
            v = 90;
          }
        ]) {
          fieldConfig.defaults = {
            min = 0;
            max = 100;
          };
          options = {
            displayMode = "lcd";
            orientation = "horizontal";
          };
        };
      })

      (panel {
        title = "Container CPU";
        x = 0;
        y = 32;
        unit = "percentunit";
        targets = [
          (q "sum by (machine) (rate(container_cpu_usage_seconds_total{machine!=\"\"}[$__rate_interval]))" "{{machine}}")
        ];
        extra.fieldConfig.defaults.custom.stacking.mode = "normal";
      })
      (panel {
        title = "Container memory";
        x = 12;
        y = 32;
        unit = "bytes";
        targets = [
          (q "sum by (machine) (container_memory_working_set_bytes{machine!=\"\"})" "{{machine}}")
        ];
        extra.fieldConfig.defaults.custom.stacking.mode = "normal";
      })
      (panel {
        title = "Disk IO";
        x = 0;
        y = 40;
        unit = "Bps";
        targets = [
          (q ''sum by (device) (rate(node_disk_read_bytes_total{instance="homelab"}[$__rate_interval]))'' "{{device}} read")
          ((q ''-sum by (device) (rate(node_disk_written_bytes_total{instance="homelab"}[$__rate_interval]))'' "{{device}} write") // { refId = "B"; })
        ];
      })
      (panel {
        title = "Network";
        x = 12;
        y = 40;
        unit = "bps";
        targets = [
          (q ''8 * rate(node_network_receive_bytes_total{device!~"lo|veth.*|mv-.*"}[$__rate_interval])'' "{{instance}} {{device}} in")
          ((q ''-8 * rate(node_network_transmit_bytes_total{device!~"lo|veth.*|mv-.*"}[$__rate_interval])'' "{{instance}} {{device}} out") // { refId = "B"; })
        ];
      })

      (panel {
        title = "Errors in the logs";
        type = "logs";
        x = 0;
        y = 48;
        w = 24;
        h = 12;
        targets = [
          {
            datasource = loki;
            expr = ''{job="systemd-journal", level=~"emerg|alert|crit|error"}'';
            refId = "A";
          }
        ];
        extra = {
          datasource = loki;
          options = {
            showTime = true;
            wrapLogMessage = true;
            sortOrder = "Descending";
          };
        };
      })
    ];
  };

  nodeFull = pkgs.fetchurl {
    name = "node-exporter-full.json";
    url = "https://grafana.com/api/dashboards/1860/revisions/46/download";
    hash = "sha256-5Y3cXcU11MkB+U2pZIvD49Wue2946Y4YW86LKJlhzqM=";
  };
in
pkgs.linkFarm "grafana-dashboards" [
  {
    name = "homelab.json";
    path = pkgs.writeText "homelab.json" (builtins.toJSON homelab);
  }
  {
    name = "node-full.json";
    path = nodeFull;
  }
]
