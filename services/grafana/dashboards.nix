# Provisioned dashboards (folder "Homelab", read-only in the UI; "Save as"
# to experiment):
#
#   homelab.json     the overview, in tabs (dashboard schema v2, Grafana 12+):
#                    Services   what runs, what does not and why, space per
#                               service, history, logs of one service
#                    Storage    NVMe / pool usage, per service over time
#                    Disks      SMART of every disk: health, damage
#                               counters, NVMe wear, every attribute
#                    Host       CPU, memory, temperatures, disks, network
#                    Containers CPU / memory / IO per container
#                    Probes     every probe, from inside and outside, certs
#                    nginx      connections, traffic per vhost, status
#                               codes; where the clients come from (map,
#                               countries, IPs, providers)
#                    Logs       errors of everything
#   node-full.json   "Node Exporter Full" (grafana.com 1860), per machine
#
# The v2 format here is what Grafana itself produces when it converts a
# classic dashboard (GET /apis/dashboard.grafana.app/v2beta1/...), plus a
# TabsLayout.
{
  pkgs,
  lib,
  inventory,
}:
let
  inherit (lib)
    concatMap
    concatStringsSep
    filterAttrs
    attrNames
    imap0
    optionalAttrs
    ;

  serviceNodes = filterAttrs (_: n: n.service != null) inventory.nodes;
  running = attrNames (filterAttrs (_: n: n.autoStart) serviceNodes);
  # PromQL regex of the container units that should be running
  runningUnits = "container@(${concatStringsSep "|" running})\\\\.service";
  # the container units of the services picked in $service
  svcUnit = "container@($service)\\\\.service";

  fsFilter = ''fstype!~"tmpfs|ramfs|squashfs|overlay"'';

  # --- building blocks ----------------------------------------------------

  refIds = [
    "A"
    "B"
    "C"
    "D"
    "E"
    "F"
  ];

  # one query; `source` is "thanos" (PromQL) or "loki" (LogQL)
  q =
    expr:
    {
      legend ? null,
      instant ? false,
      table ? false,
      source ? "thanos",
    }:
    {
      inherit
        expr
        legend
        instant
        table
        source
        ;
    };

  mkQuery = refId: x: {
    kind = "PanelQuery";
    spec = {
      inherit refId;
      hidden = false;
      query = {
        kind = "DataQuery";
        group = if x.source == "loki" then "loki" else "prometheus";
        version = "v0";
        datasource.name = x.source;
        spec = {
          inherit (x) expr;
        }
        // optionalAttrs (x.legend != null) { legendFormat = x.legend; }
        // optionalAttrs x.instant {
          instant = true;
          range = false;
        }
        // optionalAttrs x.table { format = "table"; }
        // optionalAttrs (x.source == "loki") { queryType = if x.instant then "instant" else "range"; };
      };
    };
  };

  # a panel; returns a function of its id (assigned when laid out)
  panel =
    {
      title,
      viz ? "timeseries",
      queries,
      description ? "",
      unit ? null,
      defaults ? { },
      overrides ? [ ],
      options ? { },
      transformations ? [ ],
    }:
    id: {
      kind = "Panel";
      spec = {
        inherit id title description;
        links = [ ];
        data = {
          kind = "QueryGroup";
          spec = {
            queries = imap0 (i: mkQuery (builtins.elemAt refIds i)) queries;
            transformations = map (t: {
              kind = t.id;
              spec = t;
            }) transformations;
            queryOptions = { };
          };
        };
        vizConfig = {
          kind = "VizConfig";
          group = viz;
          version = "";
          spec = {
            inherit options;
            fieldConfig = {
              defaults = defaults // optionalAttrs (unit != null) { inherit unit; };
              inherit overrides;
            };
          };
        };
      };
    };

  at = x: y: w: h: p: {
    inherit
      x
      y
      w
      h
      p
      ;
  };

  thresholds = steps: {
    mode = "absolute";
    steps = map (s: {
      color = builtins.elemAt s 0;
      value = builtins.elemAt s 1;
    }) steps;
  };

  stat =
    args:
    panel (
      args
      // {
        viz = "stat";
        options = {
          reduceOptions = {
            calcs = [ "lastNotNull" ];
            fields = "";
            values = false;
          };
          colorMode = "background";
          graphMode = "none";
          textMode = "auto";
          justifyMode = "auto";
          orientation = "auto";
          wideLayout = true;
        }
        // (args.options or { });
      }
    );

  stacked = {
    custom.stacking = {
      mode = "normal";
      group = "A";
    };
  };

  # --- service state ------------------------------------------------------
  #
  # 1 running, 0.5 running with failed units inside, 0 down (container not
  # active or its port not answering). Only containers with autoStart.

  serviceState = ''
    min by (service) (
        label_replace(node_systemd_unit_state{instance="homelab", state="active", name=~"${runningUnits}", name=~"${svcUnit}"}, "service", "$1", "name", "container@(.+)\\.service")
      or
        label_replace(probe_success{prober="homelab", module="tcp_connect", probe=~"$service"}, "service", "$1", "probe", "(.+)")
      or
        label_replace(0.5 * (count by (machine) (homelab_container_unit_failed{machine=~"$service"}) > bool 0), "service", "$1", "machine", "(.+)")
    )'';

  stateMappings = [
    {
      type = "value";
      options = {
        "1" = {
          text = "running";
          color = "green";
          index = 0;
        };
        "0.5" = {
          text = "degraded";
          color = "orange";
          index = 1;
        };
        "0" = {
          text = "DOWN";
          color = "red";
          index = 2;
        };
      };
    }
  ];

  # one row per problem: service, reason, detail
  #   rl dst replacement src regex expr   = label_replace(expr, ...)
  rl =
    dst: repl: src: regex: expr:
    ''label_replace(${expr}, "${dst}", "${repl}", "${src}", "${regex}")'';
  set = dst: value: rl dst value "" "";
  copy = dst: src: rl dst "$1" src "(.+)";
  problems = concatStringsSep "\nor\n" [
    # container not active: its state (failed, inactive, activating, ...)
    (copy "detail" "name" (
      rl "reason" "container is $1" "state" "(.+)" (
        rl "service" "$1" "name" "container@(.+)\\\\.service"
          ''node_systemd_unit_state{instance="homelab", name=~"${runningUnits}", name=~"${svcUnit}", state!="active"} == 1''
      )
    ))
    (copy "detail" "unit" (
      set "reason" "unit failed inside the container" (copy "service" "machine" ''homelab_container_unit_failed{machine=~"$service"}'')
    ))
    (set "detail" "systemctl -M <service> list-units did not answer" (
      set "reason" "units inside could not be listed" (
        copy "service" "machine" ''homelab_container_scrape_ok{machine=~"$service"} == 0''
      )
    ))
    (copy "detail" "instance" (
      set "reason" "port not answering" (
        copy "service" "probe" ''probe_success{module="tcp_connect", probe=~"$service"} == 0''
      )
    ))
    (copy "detail" "instance" (
      rl "reason" "website down, seen from $1" "prober" "(.+)" (
        copy "service" "probe" ''probe_success{module="http_up", probe=~"$service"} == 0''
      )
    ))
    (copy "detail" "name" (
      set "reason" "unit failed" (
        copy "service" "instance" ''node_systemd_unit_state{state="failed", name!~"container@.+", instance=~"$service"} == 1''
      )
    ))
  ];

  # --- space ----------------------------------------------------------------

  rootBytes = ''sum by (service) (label_replace(homelab_container_root_bytes{machine=~"$service"}, "service", "$1", "machine", "(.+)"))'';
  poolBytes = ''sum by (service) (label_replace(homelab_zfs_dataset_used_bytes{machine=~"$service"}, "service", "$1", "machine", "(.+)"))'';
  snapBytes = ''sum by (service) (label_replace(homelab_zfs_dataset_snapshots_bytes{machine=~"$service"}, "service", "$1", "machine", "(.+)"))'';

  # --- tabs -----------------------------------------------------------------
  #
  # Tables built from several queries ("merge" transformation) join rows
  # whose shared columns are equal. Every such query is aggregated
  # (max/sum by ...) down to the label columns the table shows, otherwise
  # __name__, instance, receive, ... differ and nothing is joined.

  servicesTab = {
    title = "Services";
    items = [
      (at 0 0 6 4 (stat {
        title = "Down";
        queries = [ (q "count(${serviceState} == 0) or vector(0)" { instant = true; }) ];
        defaults.thresholds = thresholds [
          [
            "green"
            null
          ]
          [
            "red"
            1
          ]
        ];
      }))
      (at 6 0 6 4 (stat {
        title = "Degraded";
        description = "Running, but with failed units inside";
        queries = [ (q "count(${serviceState} == 0.5) or vector(0)" { instant = true; }) ];
        defaults.thresholds = thresholds [
          [
            "green"
            null
          ]
          [
            "orange"
            1
          ]
        ];
      }))
      (at 12 0 6 4 (stat {
        title = "Running";
        queries = [ (q "count(${serviceState} == 1) or vector(0)" { instant = true; }) ];
        defaults.thresholds = thresholds [
          [
            "blue"
            null
          ]
        ];
      }))
      (at 18 0 6 4 (stat {
        title = "Problems";
        description = "Rows in the table below";
        queries = [ (q "count(${problems}) or vector(0)" { instant = true; }) ];
        defaults.thresholds = thresholds [
          [
            "green"
            null
          ]
          [
            "red"
            1
          ]
        ];
      }))

      (at 0 4 24 7 (stat {
        title = "Service status";
        description = "Every container that starts at boot: container active, its port answers (probe from the host), no failed units inside.";
        queries = [
          (q serviceState {
            legend = "{{service}}";
            instant = true;
          })
        ];
        defaults = {
          mappings = stateMappings;
          color.mode = "thresholds";
          thresholds = thresholds [
            [
              "red"
              null
            ]
            [
              "orange"
              0.5
            ]
            [
              "green"
              1
            ]
          ];
        };
        options = {
          textMode = "value_and_name";
          text.titleSize = 14;
        };
      }))

      (at 0 11 24 8 (panel {
        title = "What is wrong, and why";
        viz = "table";
        description = "Empty when everything runs. Details: the failed unit, the address that does not answer, or the container state. The logs below show the errors.";
        queries = [
          (q problems {
            instant = true;
            table = true;
          })
        ];
        transformations = [
          {
            id = "filterFieldsByName";
            options.include.names = [
              "service"
              "reason"
              "detail"
            ];
          }
          {
            id = "organize";
            options = {
              indexByName = {
                service = 0;
                reason = 1;
                detail = 2;
              };
              renameByName = {
                service = "Service";
                reason = "Problem";
                detail = "Detail";
              };
            };
          }
          {
            id = "sortBy";
            options.sort = [ { field = "Service"; } ];
          }
        ];
        defaults.noValue = "Everything is running";
        options = {
          showHeader = true;
          cellHeight = "sm";
        };
      }))

      (at 0 19 24 8 (panel {
        title = "History";
        viz = "state-timeline";
        queries = [ (q serviceState { legend = "{{service}}"; }) ];
        defaults = {
          mappings = stateMappings;
          color.mode = "thresholds";
          thresholds = thresholds [
            [
              "red"
              null
            ]
            [
              "orange"
              0.5
            ]
            [
              "green"
              1
            ]
          ];
        };
        options = {
          showValue = "never";
          mergeValues = true;
          rowHeight = 0.8;
          legend.showLegend = false;
        };
      }))

      (at 0 27 24 9 (panel {
        title = "Space per service";
        viz = "table";
        description = "System disk: the container root on the NVMe (without the pool datasets mounted inside). Pool: its datasets on the HDD pool, including snapshots. Updated every 15 minutes.";
        queries = [
          (q rootBytes {
            instant = true;
            table = true;
          })
          (q poolBytes {
            instant = true;
            table = true;
          })
          (q snapBytes {
            instant = true;
            table = true;
          })
        ];
        transformations = [
          {
            id = "merge";
            options = { };
          }
          {
            id = "organize";
            options = {
              excludeByName.Time = true;
              renameByName = {
                service = "Service";
                "Value #A" = "System disk (NVMe)";
                "Value #B" = "HDD pool";
                "Value #C" = "of which snapshots";
              };
            };
          }
          {
            id = "sortBy";
            options.sort = [
              {
                field = "System disk (NVMe)";
                desc = true;
              }
            ];
          }
        ];
        unit = "bytes";
        defaults.custom = {
          cellOptions = {
            type = "gauge";
            mode = "basic";
            valueDisplayMode = "text";
          };
        };
        overrides = [
          {
            matcher = {
              id = "byName";
              options = "Service";
            };
            properties = [
              {
                id = "custom.cellOptions";
                value.type = "auto";
              }
            ];
          }
        ];
        options.showHeader = true;
      }))

      (at 0 36 24 12 (panel {
        title = "Logs of $service (warnings and worse)";
        viz = "logs";
        queries = [
          (q ''{job="systemd-journal", instance=~"$service", level=~"emerg|alert|crit|error|warning"}'' {
            source = "loki";
          })
        ];
        options = {
          showTime = true;
          wrapLogMessage = true;
          sortOrder = "Descending";
          enableLogDetails = true;
        };
      }))
    ];
  };

  storageTab = {
    title = "Storage";
    items = [
      (at 0 0 12 5 (panel {
        title = "Filesystems";
        viz = "bargauge";
        unit = "percent";
        queries = [
          (q ''100 * (1 - node_filesystem_avail_bytes{${fsFilter}} / node_filesystem_size_bytes{${fsFilter}})'' {
            legend = "{{instance}} {{mountpoint}}";
            instant = true;
          })
        ];
        defaults = {
          min = 0;
          max = 100;
          thresholds = thresholds [
            [
              "green"
              null
            ]
            [
              "orange"
              80
            ]
            [
              "red"
              90
            ]
          ];
        };
        options = {
          displayMode = "lcd";
          orientation = "horizontal";
          showUnfilled = true;
        };
      }))
      (at 12 0 12 5 (panel {
        title = "ZFS pools (usable space)";
        description = "Used and free as the datasets see it, i.e. after parity (zpool list counts raw disk space including parity).";
        viz = "bargauge";
        unit = "percent";
        queries = [
          (q "100 * homelab_zfs_pool_used_bytes / (homelab_zfs_pool_used_bytes + homelab_zfs_pool_available_bytes)" {
            legend = "{{zpool}}";
            instant = true;
          })
        ];
        defaults = {
          min = 0;
          max = 100;
          thresholds = thresholds [
            [
              "green"
              null
            ]
            [
              "orange"
              80
            ]
            [
              "red"
              90
            ]
          ];
        };
        options = {
          displayMode = "lcd";
          orientation = "horizontal";
          showUnfilled = true;
        };
      }))
      (at 0 5 12 10 (panel {
        title = "System disk per service";
        unit = "bytes";
        queries = [ (q rootBytes { legend = "{{service}}"; }) ];
        defaults = stacked;
      }))
      (at 12 5 12 10 (panel {
        title = "HDD pool per service";
        unit = "bytes";
        queries = [ (q poolBytes { legend = "{{service}}"; }) ];
        defaults = stacked;
      }))
      (at 0 15 24 8 (panel {
        title = "Pool datasets";
        viz = "table";
        queries = [
          (q ''max by (dataset, machine, volume) (homelab_zfs_dataset_used_bytes{machine=~"$service"})'' {
            instant = true;
            table = true;
          })
          (q ''max by (dataset, machine, volume) (homelab_zfs_dataset_snapshots_bytes{machine=~"$service"})'' {
            instant = true;
            table = true;
          })
          (q ''max by (dataset, machine, volume) (homelab_zfs_dataset_available_bytes{machine=~"$service"})'' {
            instant = true;
            table = true;
          })
        ];
        transformations = [
          {
            id = "merge";
            options = { };
          }
          {
            id = "filterFieldsByName";
            options.include.names = [
              "dataset"
              "machine"
              "volume"
              "Value #A"
              "Value #B"
              "Value #C"
            ];
          }
          {
            id = "organize";
            options.renameByName = {
              dataset = "Dataset";
              machine = "Service";
              volume = "Volume";
              "Value #A" = "Used";
              "Value #B" = "Snapshots";
              "Value #C" = "Available";
            };
          }
        ];
        unit = "bytes";
      }))
    ];
  };

  # --- SMART ------------------------------------------------------------------
  #
  # ATA attributes whose raw value counts damage; any increase is bad
  #   5 reallocated sectors, 187 reported uncorrectable, 188 command timeout,
  #   196 reallocation events, 197 pending sectors, 198 offline
  #   uncorrectable, 199 UDMA CRC errors (cable / connector)
  badCounters = "5|187|188|196|197|198|199";
  attr = type: ''smartctl_device_attribute{attribute_value_type="${type}"}'';
  badRaw = ''smartctl_device_attribute{attribute_value_type="raw", attribute_id=~"${badCounters}"}'';
  byAttr = expr: "max by (device, attribute_id, attribute_name) (${expr})";

  healthMappings = [
    {
      type = "value";
      options = {
        "1" = {
          text = "PASSED";
          color = "green";
          index = 0;
        };
        "0" = {
          text = "FAILED";
          color = "red";
          index = 1;
        };
      };
    }
  ];

  byName = n: properties: {
    matcher = {
      id = "byName";
      options = n;
    };
    inherit properties;
  };
  colorBackground = {
    id = "custom.cellOptions";
    value.type = "color-background";
  };

  smartTab = {
    title = "Disks (SMART)";
    items = [
      (at 0 0 24 7 (panel {
        title = "Disks";
        viz = "table";
        description = "One row per disk. Damage = sum of the raw counters that should stay 0 (reallocated / pending / uncorrectable sectors, CRC errors) and NVMe media errors.";
        queries = [
          (q "max by (device, model_name, serial_number, firmware_version) (smartctl_device)" {
            instant = true;
            table = true;
          })
          (q "max by (device) (smartctl_device_smart_status)" {
            instant = true;
            table = true;
          })
          (q ''max by (device) (smartctl_device_temperature{temperature_type="current"})'' {
            instant = true;
            table = true;
          })
          (q "max by (device) (smartctl_device_power_on_seconds)" {
            instant = true;
            table = true;
          })
          (q ''sum by (device) (${badRaw}) or sum by (device) (smartctl_device_media_errors)'' {
            instant = true;
            table = true;
          })
          (q "max by (device) (smartctl_device_percentage_used)" {
            instant = true;
            table = true;
          })
        ];
        transformations = [
          {
            id = "merge";
            options = { };
          }
          {
            id = "filterFieldsByName";
            options.include.names = [
              "device"
              "model_name"
              "serial_number"
              "firmware_version"
              "Value #B"
              "Value #C"
              "Value #D"
              "Value #E"
              "Value #F"
            ];
          }
          {
            id = "organize";
            options.renameByName = {
              device = "Device";
              model_name = "Model";
              serial_number = "Serial";
              firmware_version = "Firmware";
              "Value #B" = "Health";
              "Value #C" = "Temperature";
              "Value #D" = "Powered on";
              "Value #E" = "Damage counters";
              "Value #F" = "Wear (NVMe)";
            };
          }
        ];
        overrides = [
          (byName "Health" [
            {
              id = "mappings";
              value = healthMappings;
            }
            colorBackground
          ])
          (byName "Temperature" [
            {
              id = "unit";
              value = "celsius";
            }
            {
              id = "thresholds";
              value = thresholds [
                [
                  "green"
                  null
                ]
                [
                  "orange"
                  45
                ]
                [
                  "red"
                  55
                ]
              ];
            }
            colorBackground
          ])
          (byName "Powered on" [
            {
              id = "unit";
              value = "s";
            }
          ])
          (byName "Damage counters" [
            {
              id = "thresholds";
              value = thresholds [
                [
                  "green"
                  null
                ]
                [
                  "red"
                  1
                ]
              ];
            }
            colorBackground
          ])
          (byName "Wear (NVMe)" [
            {
              id = "unit";
              value = "percent";
            }
            {
              id = "thresholds";
              value = thresholds [
                [
                  "green"
                  null
                ]
                [
                  "orange"
                  70
                ]
                [
                  "red"
                  90
                ]
              ];
            }
            colorBackground
          ])
        ];
        options.showHeader = true;
      }))

      (at 0 7 24 7 (panel {
        title = "Damage counters per disk (raw, should stay 0)";
        viz = "table";
        queries = [
          (q ''${badRaw}'' {
            instant = true;
            table = true;
          })
        ];
        transformations = [
          {
            id = "groupingToMatrix";
            options = {
              columnField = "attribute_name";
              rowField = "device";
              valueField = "Value";
            };
          }
        ];
        defaults = {
          thresholds = thresholds [
            [
              "green"
              null
            ]
            [
              "red"
              1
            ]
          ];
          custom.cellOptions.type = "color-background";
        };
        overrides = [
          (byName "device\\attribute_name" [
            {
              id = "custom.cellOptions";
              value.type = "auto";
            }
          ])
        ];
      }))

      (at 0 14 12 9 (panel {
        title = "Damage counters over time";
        queries = [
          (q ''${badRaw}'' {
            legend = "{{device}} {{attribute_name}}";
          })
          (q "smartctl_device_media_errors" { legend = "{{device}} media errors"; })
        ];
      }))
      (at 12 14 12 9 (panel {
        title = "Disk temperatures";
        unit = "celsius";
        queries = [
          (q ''smartctl_device_temperature{temperature_type="current"}'' { legend = "{{device}}"; })
        ];
      }))

      (at 0 23 24 8 (panel {
        title = "NVMe health";
        viz = "table";
        queries = [
          (q "max by (device) (smartctl_device_percentage_used)" {
            instant = true;
            table = true;
          })
          (q "max by (device) (smartctl_device_available_spare)" {
            instant = true;
            table = true;
          })
          (q "max by (device) (smartctl_device_available_spare_threshold)" {
            instant = true;
            table = true;
          })
          (q "max by (device) (smartctl_device_media_errors)" {
            instant = true;
            table = true;
          })
          (q "max by (device) (smartctl_device_critical_warning)" {
            instant = true;
            table = true;
          })
          (q "max by (device) (smartctl_device_bytes_written)" {
            instant = true;
            table = true;
          })
        ];
        transformations = [
          {
            id = "merge";
            options = { };
          }
          {
            id = "organize";
            options = {
              excludeByName.Time = true;
              renameByName = {
                device = "Device";
                "Value #A" = "Wear";
                "Value #B" = "Spare";
                "Value #C" = "Spare threshold";
                "Value #D" = "Media errors";
                "Value #E" = "Critical warning";
                "Value #F" = "Written";
              };
            };
          }
        ];
        overrides = [
          (byName "Wear" [
            {
              id = "unit";
              value = "percent";
            }
          ])
          (byName "Spare" [
            {
              id = "unit";
              value = "percent";
            }
          ])
          (byName "Spare threshold" [
            {
              id = "unit";
              value = "percent";
            }
          ])
          (byName "Written" [
            {
              id = "unit";
              value = "bytes";
            }
          ])
        ];
      }))

      (at 0 31 24 14 (panel {
        title = "All SMART attributes";
        viz = "table";
        description = "Every ATA attribute of every disk. Normalized values count down towards the threshold; margin = value - threshold (only for attributes with a threshold), at 0 the disk counts as failing.";
        queries = [
          (q (byAttr (attr "value")) {
            instant = true;
            table = true;
          })
          (q (byAttr (attr "worst")) {
            instant = true;
            table = true;
          })
          (q (byAttr (attr "thresh")) {
            instant = true;
            table = true;
          })
          (q (byAttr (attr "raw")) {
            instant = true;
            table = true;
          })
          (q "${byAttr (attr "value")} - ${byAttr "${attr "thresh"} > 0"}" {
            instant = true;
            table = true;
          })
        ];
        transformations = [
          {
            id = "merge";
            options = { };
          }
          {
            id = "organize";
            options = {
              excludeByName.Time = true;
              indexByName = {
                device = 0;
                attribute_id = 1;
                attribute_name = 2;
              };
              renameByName = {
                device = "Device";
                attribute_id = "ID";
                attribute_name = "Attribute";
                "Value #A" = "Value";
                "Value #B" = "Worst";
                "Value #C" = "Threshold";
                "Value #D" = "Raw";
                "Value #E" = "Margin";
              };
            };
          }
          {
            id = "sortBy";
            options.sort = [ { field = "Device"; } ];
          }
        ];
        overrides = [
          (byName "Margin" [
            {
              id = "thresholds";
              value = thresholds [
                [
                  "red"
                  null
                ]
                [
                  "orange"
                  1
                ]
                [
                  "green"
                  10
                ]
              ];
            }
            colorBackground
          ])
        ];
        options = {
          showHeader = true;
          cellHeight = "sm";
        };
      }))

      (at 0 45 24 6 (panel {
        title = "Error and self-test logs";
        viz = "table";
        queries = [
          (q "max by (device, error_log_type) (smartctl_device_error_log_count)" {
            instant = true;
            table = true;
          })
          (q "max by (device, self_test_log_type) (smartctl_device_self_test_log_error_count)" {
            instant = true;
            table = true;
          })
          (q "max by (device) (smartctl_device_num_err_log_entries)" {
            instant = true;
            table = true;
          })
        ];
        transformations = [
          {
            id = "merge";
            options = { };
          }
          {
            id = "filterFieldsByName";
            options.include.names = [
              "device"
              "error_log_type"
              "self_test_log_type"
              "Value #A"
              "Value #B"
              "Value #C"
            ];
          }
          {
            id = "organize";
            options.renameByName = {
              device = "Device";
              error_log_type = "Error log";
              self_test_log_type = "Self-test log";
              "Value #A" = "Errors logged";
              "Value #B" = "Failed self-tests";
              "Value #C" = "NVMe error log entries";
            };
          }
        ];
      }))
    ];
  };

  hostTab = {
    title = "Host";
    items = [
      (at 0 0 6 4 (stat {
        title = "Hottest sensor";
        unit = "celsius";
        queries = [ (q ''max(node_hwmon_temp_celsius{instance="homelab"})'' { instant = true; }) ];
        defaults.thresholds = thresholds [
          [
            "green"
            null
          ]
          [
            "orange"
            70
          ]
          [
            "red"
            85
          ]
        ];
      }))
      (at 6 0 6 4 (stat {
        title = "Uptime";
        unit = "s";
        queries = [ (q ''time() - node_boot_time_seconds{instance="homelab"}'' { instant = true; }) ];
        defaults.thresholds = thresholds [
          [
            "blue"
            null
          ]
        ];
      }))
      (at 12 0 6 4 (stat {
        title = "Load (5m)";
        queries = [ (q ''node_load5{instance="homelab"}'' { instant = true; }) ];
        defaults.thresholds = thresholds [
          [
            "blue"
            null
          ]
        ];
      }))
      (at 18 0 6 4 (stat {
        title = "Failed units (host)";
        queries = [
          (q ''count(node_systemd_unit_state{instance="homelab", state="failed"} == 1) or vector(0)'' {
            instant = true;
          })
        ];
        defaults.thresholds = thresholds [
          [
            "green"
            null
          ]
          [
            "red"
            1
          ]
        ];
      }))
      (at 0 4 12 8 (panel {
        title = "CPU";
        unit = "percent";
        queries = [
          (q ''100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[$__rate_interval])))'' {
            legend = "{{instance}}";
          })
        ];
      }))
      (at 12 4 12 8 (panel {
        title = "Memory used";
        unit = "percent";
        queries = [
          (q "100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)" {
            legend = "{{instance}}";
          })
        ];
      }))
      (at 0 12 12 8 (panel {
        title = "Temperatures";
        unit = "celsius";
        queries = [
          (q ''node_hwmon_temp_celsius{instance="homelab"}'' { legend = "{{chip}} {{sensor}}"; })
          (q ''smartctl_device_temperature{temperature_type="current"}'' { legend = "disk {{device}}"; })
        ];
      }))
      (at 12 12 12 8 (panel {
        title = "Disk IO";
        unit = "Bps";
        queries = [
          (q ''sum by (device) (rate(node_disk_read_bytes_total{instance="homelab"}[$__rate_interval]))'' {
            legend = "{{device}} read";
          })
          (q ''-sum by (device) (rate(node_disk_written_bytes_total{instance="homelab"}[$__rate_interval]))'' {
            legend = "{{device}} write";
          })
        ];
      }))
      (at 0 20 24 8 (panel {
        title = "Network";
        unit = "bps";
        queries = [
          (q ''8 * rate(node_network_receive_bytes_total{device!~"lo|veth.*|mv-.*"}[$__rate_interval])'' {
            legend = "{{instance}} {{device}} in";
          })
          (q ''-8 * rate(node_network_transmit_bytes_total{device!~"lo|veth.*|mv-.*"}[$__rate_interval])'' {
            legend = "{{instance}} {{device}} out";
          })
        ];
      }))
    ];
  };

  containersTab = {
    title = "Containers";
    items = [
      (at 0 0 12 10 (panel {
        title = "CPU per container";
        unit = "percentunit";
        queries = [
          (q ''sum by (machine) (rate(container_cpu_usage_seconds_total{machine=~"$service"}[$__rate_interval]))'' {
            legend = "{{machine}}";
          })
        ];
        defaults = stacked;
      }))
      (at 12 0 12 10 (panel {
        title = "Memory per container";
        unit = "bytes";
        queries = [
          (q ''sum by (machine) (container_memory_working_set_bytes{machine=~"$service"})'' {
            legend = "{{machine}}";
          })
        ];
        defaults = stacked;
      }))
      (at 0 10 24 9 (panel {
        title = "Disk IO per container";
        unit = "Bps";
        queries = [
          (q ''sum by (machine) (rate(container_fs_reads_bytes_total{machine=~"$service"}[$__rate_interval]))'' {
            legend = "{{machine}} read";
          })
          (q ''-sum by (machine) (rate(container_fs_writes_bytes_total{machine=~"$service"}[$__rate_interval]))'' {
            legend = "{{machine}} write";
          })
        ];
      }))
    ];
  };

  probesTab = {
    title = "Probes";
    items = [
      (at 0 0 24 14 (panel {
        title = "Probes";
        viz = "state-timeline";
        description = "tcp: each container's port, from the host. https: each vhost, from the host (inside) and from the VPS (outside).";
        queries = [ (q ''probe_success{probe=~"$service"}'' { legend = "{{probe}} ({{prober}})"; }) ];
        defaults = {
          mappings = [
            {
              type = "value";
              options = {
                "0" = {
                  text = "down";
                  color = "red";
                  index = 0;
                };
                "1" = {
                  text = "up";
                  color = "green";
                  index = 1;
                };
              };
            }
          ];
          color.mode = "thresholds";
        };
        options = {
          showValue = "never";
          mergeValues = true;
          legend.showLegend = false;
        };
      }))
      (at 0 14 12 9 (panel {
        title = "Response time";
        unit = "s";
        queries = [ (q ''probe_duration_seconds{probe=~"$service"}'' { legend = "{{probe}} ({{prober}})"; }) ];
      }))
      (at 12 14 12 9 (panel {
        title = "Certificates: days left";
        viz = "bargauge";
        unit = "d";
        queries = [
          (q "min by (instance) ((probe_ssl_earliest_cert_expiry - time()) / 86400)" {
            legend = "{{instance}}";
            instant = true;
          })
        ];
        defaults.thresholds = thresholds [
          [
            "red"
            null
          ]
          [
            "orange"
            14
          ]
          [
            "green"
            30
          ]
        ];
        options = {
          displayMode = "basic";
          orientation = "horizontal";
        };
      }))
    ];
  };

  # --- nginx ----------------------------------------------------------------
  #
  # Metrics: the VTS module of nix-nginx (job="nginx"), server zone
  # host="*" is the sum of all vhosts. Bytes are counted when a request
  # ends, so a long download / websocket shows up at its end.
  # Logs: nix-nginx's JSON access log (job="nginx", label vhost), with
  # GeoIP as structured metadata (country_code, country, city, lat, lon,
  # asn, as_org). Only addresses found in the GeoIP database have a
  # country_code: that is "from outside"; LAN / VPN clients have none.

  vts = m: sel: ''nginx_vts_${m}{job="nginx", ${sel}}'';
  outside = ''{job="nginx"} | country_code != ""'';

  # A Loki instant query as a table: one row per series, its labels as
  # columns, the value as `valueName`, sorted by it (largest first).
  lokiTable =
    {
      title,
      expr,
      valueName,
      columns,
      description ? "",
      unit ? null,
    }:
    panel {
      inherit title description unit;
      viz = "table";
      queries = [
        (q expr {
          instant = true;
          source = "loki";
        })
      ];
      transformations = [
        {
          id = "reduce";
          options = {
            mode = "seriesToRows";
            reducers = [ "lastNotNull" ];
            labelsToFields = true;
            includeTimeField = false;
          };
        }
        {
          id = "organize";
          options = {
            excludeByName.Field = true;
            indexByName = builtins.listToAttrs (
              imap0 (i: c: {
                name = c.name;
                value = i;
              }) columns
              ++ [
                {
                  name = "Last *";
                  value = builtins.length columns;
                }
              ]
            );
            renameByName = builtins.listToAttrs (
              map (c: {
                inherit (c) name;
                value = c.title;
              }) columns
            )
            // {
              "Last *" = valueName;
            };
          };
        }
        {
          id = "sortBy";
          options.sort = [
            {
              field = valueName;
              desc = true;
            }
          ];
        }
      ];
      options = {
        showHeader = true;
        cellHeight = "sm";
      };
    };

  col = name: title: { inherit name title; };

  nginxTab = {
    title = "nginx";
    items = [
      (at 0 0 4 4 (stat {
        title = "Connections now";
        description = "Open client connections (active = reading + writing + waiting/keep-alive)";
        queries = [ (q "sum(${vts "main_connections" ''status="active"''})" { instant = true; }) ];
        defaults.thresholds = thresholds [
          [
            "blue"
            null
          ]
        ];
      }))
      (at 4 0 4 4 (stat {
        title = "Requests / s";
        unit = "reqps";
        queries = [
          (q "sum(rate(${vts "server_requests_total" ''host="*", code="total"''}[5m]))" { instant = true; })
        ];
        defaults.thresholds = thresholds [
          [
            "blue"
            null
          ]
        ];
      }))
      (at 8 0 4 4 (stat {
        title = "Sent (time range)";
        description = "Bytes nginx sent to clients";
        unit = "bytes";
        queries = [
          (q "sum(increase(${vts "server_bytes_total" ''host="*", direction="out"''}[$__range]))" {
            instant = true;
          })
        ];
        defaults.thresholds = thresholds [
          [
            "blue"
            null
          ]
        ];
      }))
      (at 12 0 4 4 (stat {
        title = "Received (time range)";
        description = "Bytes clients sent to nginx (uploads, requests)";
        unit = "bytes";
        queries = [
          (q "sum(increase(${vts "server_bytes_total" ''host="*", direction="in"''}[$__range]))" {
            instant = true;
          })
        ];
        defaults.thresholds = thresholds [
          [
            "blue"
            null
          ]
        ];
      }))
      (at 16 0 4 4 (stat {
        title = "5xx (time range)";
        description = "Share of requests answered with a server error (backend down: 502/504)";
        unit = "percentunit";
        queries = [
          (q
            "sum(increase(${vts "server_requests_total" ''host="*", code="5xx"''}[$__range])) / sum(increase(${vts "server_requests_total" ''host="*", code="total"''}[$__range]))"
            { instant = true; }
          )
        ];
        defaults.thresholds = thresholds [
          [
            "green"
            null
          ]
          [
            "orange"
            0.01
          ]
          [
            "red"
            0.05
          ]
        ];
      }))
      (at 20 0 4 4 (stat {
        title = "Outside IPs (time range)";
        description = "Distinct client addresses from the internet (with a GeoIP match)";
        queries = [
          (q ''count(sum by (client_ip) (count_over_time(${outside} | json client_ip="client_ip" [$__range])))'' {
            instant = true;
            source = "loki";
          })
        ];
        defaults.thresholds = thresholds [
          [
            "blue"
            null
          ]
        ];
      }))

      (at 0 4 15 13 (panel {
        title = "Where the requests come from";
        viz = "geomap";
        description = "Requests from the internet in the time range, per place (DB-IP Lite: city-level, not exact). Bigger = more requests.";
        queries = [
          (q ''sum by (lat, lon, city, country) (count_over_time(${outside} [$__range]))'' {
            instant = true;
            source = "loki";
          })
        ];
        transformations = [
          {
            id = "reduce";
            options = {
              mode = "seriesToRows";
              reducers = [ "lastNotNull" ];
              labelsToFields = true;
              includeTimeField = false;
            };
          }
          {
            id = "organize";
            options = {
              excludeByName.Field = true;
              renameByName."Last *" = "Requests";
            };
          }
          {
            id = "convertFieldType";
            options = {
              fields = { };
              conversions = [
                {
                  targetField = "lat";
                  destinationType = "number";
                }
                {
                  targetField = "lon";
                  destinationType = "number";
                }
              ];
            };
          }
        ];
        options = {
          view = {
            id = "coords";
            lat = 35;
            lon = 10;
            zoom = 1.6;
            allLayers = true;
          };
          controls = {
            showZoom = true;
            mouseWheelZoom = true;
            showAttribution = true;
          };
          tooltip.mode = "details";
          basemap = {
            type = "default";
            name = "Basemap";
            config = { };
          };
          layers = [
            {
              type = "markers";
              name = "Requests";
              tooltip = true;
              location = {
                mode = "coords";
                latitude = "lat";
                longitude = "lon";
              };
              config = {
                showLegend = false;
                style = {
                  size = {
                    field = "Requests";
                    fixed = 5;
                    min = 4;
                    max = 30;
                  };
                  color.fixed = "orange";
                  opacity = 0.5;
                  symbol = {
                    mode = "fixed";
                    fixed = "img/icons/marker/circle.svg";
                  };
                };
              };
            }
          ];
        };
      }))
      (at 15 4 9 13 (lokiTable {
        title = "Countries";
        expr = ''topk(30, sum by (country) (count_over_time(${outside} [$__range])))'';
        valueName = "Requests";
        columns = [ (col "country" "Country") ];
      }))

      (at 0 17 12 10 (lokiTable {
        title = "Top client IPs (requests)";
        description = "From the internet, in the time range";
        expr = ''topk(30, sum by (client_ip, country, city, as_org) (count_over_time(${outside} | json client_ip="client_ip" [$__range])))'';
        valueName = "Requests";
        columns = [
          (col "client_ip" "IP")
          (col "country" "Country")
          (col "city" "City")
          (col "as_org" "Provider")
        ];
      }))
      (at 12 17 12 10 (lokiTable {
        title = "Top client IPs (data sent to them)";
        description = "From the internet, in the time range";
        unit = "bytes";
        expr = ''topk(30, sum by (client_ip, country, as_org) (sum_over_time(${outside} | json client_ip="client_ip", bytes_sent="bytes_sent" | unwrap bytes_sent [$__range])))'';
        valueName = "Sent";
        columns = [
          (col "client_ip" "IP")
          (col "country" "Country")
          (col "as_org" "Provider")
        ];
      }))
      (at 0 27 12 9 (lokiTable {
        title = "Providers (AS)";
        description = "Networks the outside requests come from: ISPs, mobile carriers, cloud hosters (often bots)";
        expr = ''topk(30, sum by (asn, as_org) (count_over_time(${outside} [$__range])))'';
        valueName = "Requests";
        columns = [
          (col "as_org" "Provider")
          (col "asn" "AS")
        ];
      }))
      (at 12 27 12 9 (lokiTable {
        title = "Vhosts asked from outside";
        expr = ''topk(30, sum by (vhost) (count_over_time(${outside} [$__range])))'';
        valueName = "Requests";
        columns = [ (col "vhost" "Vhost") ];
      }))

      (at 0 36 12 9 (panel {
        title = "Connections";
        description = "reading: reading the request header; writing: sending the response (also open websockets / streams); waiting: idle keep-alive";
        queries = [
          (q ''sum by (status) (${vts "main_connections" ''status=~"reading|writing|waiting"''})'' {
            legend = "{{status}}";
          })
        ];
        defaults = stacked;
      }))
      (at 12 36 12 9 (panel {
        title = "New connections and requests";
        unit = "reqps";
        queries = [
          (q ''sum(rate(${vts "main_connections" ''status="accepted"''}[$__rate_interval]))'' {
            legend = "connections / s";
          })
          (q ''sum(rate(${vts "main_connections" ''status="requests"''}[$__rate_interval]))'' {
            legend = "requests / s";
          })
        ];
      }))
      (at 0 45 12 10 (panel {
        title = "Sent per vhost";
        unit = "Bps";
        queries = [
          (q ''sum by (host) (rate(${vts "server_bytes_total" ''host!="*", direction="out"''}[$__rate_interval]))'' {
            legend = "{{host}}";
          })
        ];
        defaults = stacked;
      }))
      (at 12 45 12 10 (panel {
        title = "Received per vhost";
        unit = "Bps";
        queries = [
          (q ''sum by (host) (rate(${vts "server_bytes_total" ''host!="*", direction="in"''}[$__rate_interval]))'' {
            legend = "{{host}}";
          })
        ];
        defaults = stacked;
      }))
      (at 0 55 12 9 (panel {
        title = "Responses by status";
        unit = "reqps";
        queries = [
          (q ''sum by (code) (rate(${vts "server_requests_total" ''host="*", code=~"[1-5]xx"''}[$__rate_interval]))'' {
            legend = "{{code}}";
          })
        ];
        defaults = stacked;
        overrides = [
          (byName "5xx" [
            {
              id = "color";
              value = {
                mode = "fixed";
                fixedColor = "red";
              };
            }
          ])
          (byName "4xx" [
            {
              id = "color";
              value = {
                mode = "fixed";
                fixedColor = "orange";
              };
            }
          ])
        ];
      }))
      (at 12 55 12 9 (panel {
        title = "Response time per vhost (p95)";
        description = "Until the last byte is sent: long downloads and streams are slow by nature";
        unit = "s";
        queries = [
          (q ''histogram_quantile(0.95, sum by (host, le) (rate(${vts "server_request_duration_seconds_bucket" ''host!="*"''}[$__rate_interval])))'' {
            legend = "{{host}}";
          })
        ];
      }))
      (at 0 64 24 9 (panel {
        title = "Per vhost (time range)";
        viz = "table";
        queries = [
          (q ''sum by (host) (increase(${vts "server_bytes_total" ''host!="*", direction="out"''}[$__range]))'' {
            instant = true;
            table = true;
          })
          (q ''sum by (host) (increase(${vts "server_bytes_total" ''host!="*", direction="in"''}[$__range]))'' {
            instant = true;
            table = true;
          })
          (q ''sum by (host) (increase(${vts "server_requests_total" ''host!="*", code="total"''}[$__range]))'' {
            instant = true;
            table = true;
          })
          (q ''sum by (host) (increase(${vts "server_requests_total" ''host!="*", code="5xx"''}[$__range]))'' {
            instant = true;
            table = true;
          })
        ];
        transformations = [
          {
            id = "merge";
            options = { };
          }
          {
            id = "organize";
            options = {
              excludeByName.Time = true;
              renameByName = {
                host = "Vhost";
                "Value #A" = "Sent";
                "Value #B" = "Received";
                "Value #C" = "Requests";
                "Value #D" = "5xx";
              };
            };
          }
          {
            id = "sortBy";
            options.sort = [
              {
                field = "Sent";
                desc = true;
              }
            ];
          }
        ];
        overrides = [
          (byName "Sent" [
            {
              id = "unit";
              value = "bytes";
            }
          ])
          (byName "Received" [
            {
              id = "unit";
              value = "bytes";
            }
          ])
          (byName "Requests" [
            {
              id = "decimals";
              value = 0;
            }
          ])
          (byName "5xx" [
            {
              id = "decimals";
              value = 0;
            }
          ])
        ];
        options.showHeader = true;
      }))
      (at 0 73 24 8 (panel {
        title = "Outside requests per country";
        queries = [
          (q ''topk(10, sum by (country) (count_over_time(${outside} [$__auto])))'' {
            legend = "{{country}}";
            source = "loki";
          })
        ];
        defaults = stacked // {
          custom = stacked.custom // {
            drawStyle = "bars";
            fillOpacity = 80;
          };
        };
      }))
      (at 0 81 24 14 (panel {
        title = "Requests from outside";
        viz = "logs";
        description = "Newest first. Open a line for country, city and provider (structured metadata).";
        queries = [ (q outside { source = "loki"; }) ];
        options = {
          showTime = true;
          wrapLogMessage = false;
          sortOrder = "Descending";
          enableLogDetails = true;
        };
      }))
    ];
  };

  logsTab = {
    title = "Logs";
    items = [
      (at 0 0 24 8 (panel {
        title = "Log lines per machine";
        viz = "timeseries";
        queries = [
          (q ''sum by (instance) (count_over_time({job="systemd-journal"}[$__auto]))'' {
            legend = "{{instance}}";
            source = "loki";
          })
        ];
        defaults = stacked // {
          custom = stacked.custom // {
            drawStyle = "bars";
            fillOpacity = 80;
          };
        };
      }))
      (at 0 8 24 16 (panel {
        title = "Errors everywhere";
        viz = "logs";
        queries = [
          (q ''{job="systemd-journal", level=~"emerg|alert|crit|error"}'' {
            source = "loki";
          })
        ];
        options = {
          showTime = true;
          wrapLogMessage = true;
          sortOrder = "Descending";
          enableLogDetails = true;
        };
      }))
    ];
  };

  tabs = [
    servicesTab
    storageTab
    smartTab
    hostTab
    containersTab
    probesTab
    nginxTab
    logsTab
  ];

  # panel ids 1.. across all tabs
  numbered =
    (lib.foldl'
      (acc: t: {
        next = acc.next + builtins.length t.items;
        tabs = acc.tabs ++ [ (t // { items = imap0 (j: it: it // { id = acc.next + j; }) t.items; }) ];
      })
      {
        next = 1;
        tabs = [ ];
      }
      tabs
    ).tabs;

  name = id: "panel-${toString id}";

  homelab = {
    apiVersion = "dashboard.grafana.app/v2beta1";
    kind = "Dashboard";
    metadata.name = "homelab";
    spec = {
      title = "Homelab";
      tags = [ "homelab" ];
      editable = true;
      liveNow = false;
      preload = false;
      cursorSync = "Crosshair";
      links = [ ];
      annotations = [ ];
      timeSettings = {
        from = "now-24h";
        to = "now";
        timezone = "browser";
        autoRefresh = "1m";
        autoRefreshIntervals = [
          "30s"
          "1m"
          "5m"
          "15m"
          "1h"
        ];
        hideTimepicker = false;
        fiscalYearStartMonth = 0;
      };
      variables = [
        {
          kind = "CustomVariable";
          spec = {
            name = "service";
            label = "Service";
            # "All" = every series, also those whose service is not in the
            # list (https probes are named after the host name)
            allValue = ".*";
            query = concatStringsSep "," (
              attrNames serviceNodes
              ++ [
                "homelab"
                "hetzner-vps-01"
              ]
            );
            current = {
              text = [ "All" ];
              value = [ "$__all" ];
            };
            options = [ ];
            multi = true;
            includeAll = true;
            hide = "dontHide";
            skipUrlSync = false;
            allowCustomValue = true;
          };
        }
      ];
      elements = builtins.listToAttrs (
        concatMap (
          t:
          map (it: {
            name = name it.id;
            value = it.p it.id;
          }) t.items
        ) numbered
      );
      layout = {
        kind = "TabsLayout";
        spec.tabs = map (t: {
          kind = "TabsLayoutTab";
          spec = {
            inherit (t) title;
            layout = {
              kind = "GridLayout";
              spec.items = map (it: {
                kind = "GridLayoutItem";
                spec = {
                  inherit (it) x y;
                  width = it.w;
                  height = it.h;
                  element = {
                    kind = "ElementReference";
                    name = name it.id;
                  };
                };
              }) t.items;
            };
          };
        }) numbered;
      };
    };
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
