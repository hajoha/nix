# Metrics storage: Thanos with a filesystem "bucket" in this container.
#
#   Alloy ──remote write──▶ receive :19291   newest ~2h in memory, then 2h
#                              │              blocks into the bucket
#                              ▼
#                    /var/lib/thanos/bucket
#                     ▲                  ▲
#             compact │                  │ store :10905 (gRPC)
#   downsample + retention:              │
#     raw 15d, 5m 90d, 1h 5y             │
#                                        │
#   Grafana ──PromQL──▶ query :10902 ────┴── + receive :10907 (recent data)
#
# Query picks the resolution from the step of the graph
# (--query.auto-downsampling): weeks/years read the 5m/1h blocks. Older than
# 15 days there is no raw data, zooming in shows the 5m (then 1h) points.
# Downsampled blocks exist for data older than 40h (5m) and 10d (1h).
#
# The bucket is plain files; moving to S3/MinIO later only changes
# `objstore`.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  dataDir = "/var/lib/thanos";
  bucket = "${dataDir}/bucket";

  objstore = pkgs.writeText "objstore.yaml" (
    builtins.toJSON {
      type = "FILESYSTEM";
      config.directory = bucket;
    }
  );

  ports = {
    query = {
      http = 10902; # Grafana datasource
      grpc = 10901;
    };
    receive = {
      http = 10909;
      grpc = 10907;
      remoteWrite = 19291; # Alloy
    };
    store = {
      http = 10906;
      grpc = 10905;
    };
    compact.http = 10912;
  };

  # all components share the bucket, so one fixed user instead of the
  # module's DynamicUser
  asThanos = {
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "thanos";
      Group = "thanos";
    };
  };
in
{
  users.users.thanos = {
    isSystemUser = true;
    group = "thanos";
    home = dataDir;
  };
  users.groups.thanos = { };

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 thanos thanos -"
    "d ${bucket} 0750 thanos thanos -"
  ];

  services.thanos = {
    # The module's typed options cannot pass the flags below; `arguments`
    # replaces them (with them, all of them).
    receive = {
      enable = true;
      arguments = [
        "--http-address=127.0.0.1:${toString ports.receive.http}"
        "--grpc-address=127.0.0.1:${toString ports.receive.grpc}"
        "--remote-write.address=0.0.0.0:${toString ports.receive.remoteWrite}"
        "--tsdb.path=/var/lib/thanos-receive"
        # local copy only; uploaded blocks are served by store
        "--tsdb.retention=1d"
        # backlog from Alloy's WAL after an outage (Alloy keeps up to 8h);
        # needs vertical compaction in compact
        "--tsdb.out-of-order.time-window=8h"
        # samples dated in the future (clock skew) are rejected beyond this
        "--tsdb.too-far-in-future.time-window=5m"
        "--objstore.config-file=${objstore}"
        # external label of this block stream (must stay the same); single
        # quotes for systemd, which would otherwise strip the inner ones
        # (thanos: "unquote label value")
        "'--label=receive=\"nix-thanos\"'"
      ];
    };

    store = {
      enable = true;
      arguments = [
        "--http-address=127.0.0.1:${toString ports.store.http}"
        "--grpc-address=127.0.0.1:${toString ports.store.grpc}"
        "--data-dir=/var/lib/thanos-store"
        "--objstore.config-file=${objstore}"
        "--index-cache-size=256MB"
        "--chunk-pool-size=1GB"
      ];
    };

    compact = {
      enable = true;
      arguments = [
        "--http-address=127.0.0.1:${toString ports.compact.http}"
        "--data-dir=/var/lib/thanos-compact"
        "--objstore.config-file=${objstore}"
        "--wait"
        "--wait-interval=5m"
        "--retention.resolution-raw=15d"
        "--retention.resolution-5m=90d"
        "--retention.resolution-1h=5y"
        # overlapping blocks from out-of-order ingestion
        "--compact.enable-vertical-compaction"
      ];
    };

    query = {
      enable = true;
      arguments = [
        "--http-address=0.0.0.0:${toString ports.query.http}"
        "--grpc-address=127.0.0.1:${toString ports.query.grpc}"
        "--endpoint=127.0.0.1:${toString ports.receive.grpc}"
        "--endpoint=127.0.0.1:${toString ports.store.grpc}"
        "--query.auto-downsampling"
        "--query.timeout=2m"
      ];
    };
  };

  systemd.services = {
    thanos-receive = asThanos // {
      after = [ "systemd-tmpfiles-setup.service" ];
    };
    thanos-store = asThanos // {
      after = [ "systemd-tmpfiles-setup.service" ];
    };
    thanos-compact = asThanos // {
      after = [ "systemd-tmpfiles-setup.service" ];
    };
    thanos-query = asThanos;
  };

  environment.systemPackages = [ config.services.thanos.package ];

  # Firewall ports come from the inventory (tcp in nodes.nix)
}
