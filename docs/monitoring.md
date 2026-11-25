# Monitoring

Logs, metrics, uptime probes and alerts for the homelab host, all of its
containers and the Hetzner VPS.

```
 homelab host (10.60.0.4)                                 nix-loki 10.60.1.27
 ┌───────────────────────────────────────────┐  logs    ┌──────────────────────┐
 │ Alloy (one, on the host)                  │ ───────▶ │ Loki :3100, 30 days  │◀─┐
 │  · host journal                           │          └──────────────────────┘  │
 │  · every container's journal (from disk)  │                                    │ LogQL
 │  · node metrics: CPU, RAM, disks, temps,  │  metrics  nix-thanos 10.60.1.28    │
 │    ZFS, network, systemd units            │ ───────▶ ┌──────────────────────┐  │
 │  · cAdvisor: CPU/RAM/IO per container     │  remote  │ receive :19291       │  │
 │  · failed units inside containers         │  write   │ store / compact      │  │
 │  · SMART (smartctl exporter)              │          │ query :10902         │◀─┤ PromQL
 │  · probes: tcp per container, https per   │          │ raw 15d · 5m 90d ·   │  │
 │    nginx vhost                            │          │ 1h 5y                │  │
 └───────────────────────────────────────────┘          └──────────────────────┘  │
                                                          ▲                       │
 hetzner-vps-01                                           │ WireGuard             │
 ┌───────────────────────────────────────────┐            │ via home-openwrt      │
 │ Alloy: own journal + node metrics,        │ ───────────┘                       │
 │ https probes of the public vhosts         │                    nix-grafana 10.60.1.25
 │ (what the internet sees)                  │                    ┌───────────────┴──┐
 └───────────────────────────────────────────┘                    │ dashboards,      │
                                                                  │ alert rules      │
                                                                  └──────────────────┘
```

## Contents

- [Design in short](#design-in-short)
- [Where things live](#where-things-live)
- [What is collected](#what-is-collected)
- [Labels](#labels)
- [Storage and retention](#storage-and-retention)
- [Timestamps, outages and backlog](#timestamps-outages-and-backlog)
- [Probes](#probes)
- [Grafana: dashboards](#grafana-dashboards)
- [Grafana: alerts](#grafana-alerts)
- [Notifications and outside checks (VPS)](#notifications-and-outside-checks-vps)
- [Network paths](#network-paths)
- [Operating it](#operating-it)
- [Extending it](#extending-it)
- [Troubleshooting](#troubleshooting)
- [Known gaps and to-dos](#known-gaps-and-to-dos)

## Design in short

- **One agent per machine.** Grafana Alloy runs on the homelab *host* and on
  the VPS. Containers run no agent. The host reads each container's journal
  straight from the container root on disk, and its resource use from the
  container's cgroup. A new container is therefore monitored as soon as it
  is in `inventory/nodes.nix`.
- **Thanos for metrics.** It was picked over VictoriaMetrics and InfluxDB
  because open-source Thanos downsamples old data by itself, which gives
  full resolution for two weeks and coarser data after that (see
  [Storage and retention](#storage-and-retention)). It speaks PromQL, so
  Grafana and the community dashboards work as they are.
- **Loki for logs**, kept for 30 days.
- **Grafana alerting**: alert rules are provisioned from Nix, and there is no
  Alertmanager. Notifications go to ntfy on the VPS, and Gatus there checks
  the homelab from outside.
- **Everything is in Nix.** Datasources, dashboards and alert rules are
  provisioned and read-only in the UI. To change one, change the Nix file.

## Where things live

| What | File |
|---|---|
| Alloy agent module (journal → Loki, node metrics, probes → Thanos) | `modules/nixos/alloy-agent.nix` |
| Homelab host agent: container journals, cAdvisor, SMART, failed units in containers, probe list | `hosts/homelab/monitoring.nix` |
| VPS agent: own journal and metrics, probes of the public vhosts | `hosts/hetzner-vps-01/monitoring.nix` |
| Public vhost list handed to the VPS | `flake/hosts.nix` (`publicVhosts`) |
| WireGuard route from the VPS to nix-loki and nix-thanos | `hosts/hetzner-vps-01/wireguard-peers.json` (`routes` of home-openwrt) |
| Thanos (receive, store, compact, query) | `services/thanos/default.nix` |
| Loki (storage, retention) | `services/loki/default.nix` |
| Grafana: datasources, dashboard provider, SSO | `services/grafana/default.nix` |
| Dashboards | `services/grafana/dashboards.nix` |
| Alert rules | `services/grafana/alerts.nix` |
| Contact point and policy (ntfy) | `services/grafana/default.nix` |
| ntfy, Traefik, Gatus (outside checks) on the VPS | `hosts/hetzner-vps-01/notify.nix` |
| Containers, IPs, firewall ports | `inventory/nodes.nix` (`nix-loki`, `nix-thanos`, `nix-grafana`) |

Alloy loads every `/etc/alloy/*.alloy` file as one configuration.
`base.alloy` comes from the module and defines `loki.write.default`,
`loki.relabel.journal` and `prometheus.remote_write.default`. Other files,
such as the host's `homelab.alloy`, can use these components.

## What is collected

| Source | Where it runs | What | Interval |
|---|---|---|---|
| Journal of the machine itself | host, VPS | all units, `job="systemd-journal"` | live |
| Journal of each container | host | read from `/var/lib/nixos-containers/<name>/var/log/journal` | live |
| `prometheus.exporter.unix` (node exporter) | host, VPS | CPU, memory, load, filesystems, disk IO, network, hwmon temperatures, ZFS, systemd units (`*.service`, `*.timer`, `*.mount`), textfile `*.prom` | 15s |
| cAdvisor | host | CPU, memory and disk IO of each `container@<name>.service` cgroup (`job="cadvisor"`) | 15s |
| `homelab-disk-usage` (systemd timer, idle IO) | host | `homelab_container_root_bytes{machine}` (`du -sx` of each container root, without the pool datasets inside), `homelab_zfs_dataset_{used,snapshots,available}_bytes{machine,volume,dataset}` (`zfs list` under `<pool>/containers`), `homelab_zfs_pool_{used,available}_bytes` (usable, from the pool's root dataset), `homelab_zpool_{size,allocated,free}_bytes` (raw, with parity), written to `/var/lib/homelab-metrics/disk.prom` | 15m |
| `homelab-container-units` (systemd timer) | host | `homelab_container_unit_failed{machine,unit}` and `homelab_container_scrape_ok{machine}`, from `systemctl -M <name> list-units --state=failed`, written to `/var/lib/homelab-metrics/containers.prom` | 1m |
| smartctl exporter (`127.0.0.1:9633`) | host | SMART health, disk temperatures, counters (`job="smartctl"`) | 60s scrape, smartctl at most every 5m |
| Blackbox probes | host, VPS | `probe_success`, durations, TLS expiry (`job="blackbox"`) | 30s |

Home Assistant data is not in Thanos. HA keeps using its recorder in
nix-postgres (see [Known gaps](#known-gaps-and-to-dos)).

## Labels

Logs (Loki):

| Label | Value |
|---|---|
| `job` | `systemd-journal` |
| `instance` | `homelab`, `hetzner-vps-01`, or the container name (`nix-paperless`, …) |
| `unit` | systemd unit, e.g. `paperless-web.service` |
| `level` | journald priority: `emerg`, `alert`, `crit`, `error`, `warning`, `notice`, `info`, `debug` |

Metrics (Thanos):

| Label | Where | Value |
|---|---|---|
| `instance` | all | machine: `homelab` / `hetzner-vps-01`. For probes, the probed target (`10.60.1.23:3005`, `https://grafana.hackler.io`) |
| `job` | all | `node`, `cadvisor`, `smartctl`, `blackbox` |
| `machine` | cAdvisor, container units | container name, e.g. `nix-immich` |
| `probe` | probes | probe name: the node name for tcp probes, the hostname for https probes |
| `prober` | probes | which machine ran the probe: `homelab` (inside) or `hetzner-vps-01` (outside) |
| `module` | probes | `tcp_connect` or `http_up` |
| `receive` | all (external label) | `nix-thanos`, added by Thanos Receive. Do not change it, because blocks with a different label count as a separate stream |

## Storage and retention

### Metrics: Thanos (nix-thanos)

All components run in one container and share a "bucket", which is a plain
directory (`/var/lib/thanos/bucket` inside the container,
`/var/lib/nixos-containers/nix-thanos/var/lib/thanos/bucket` on the host).

| Component | Port | Role |
|---|---|---|
| receive | `:19291` remote write (all interfaces), gRPC `127.0.0.1:10907` | Takes Alloy's remote writes into a local TSDB. Every 2h it cuts a block and uploads it to the bucket. It keeps 1 day locally. |
| store | gRPC `127.0.0.1:10905` | Serves the blocks in the bucket to query. |
| compact | `127.0.0.1:10912` | Compacts blocks, downsamples them and deletes data past its retention. It runs every 5 minutes (`--wait`). |
| query | `:10902` (Grafana), gRPC `127.0.0.1:10901` | PromQL over receive (newest data) and store (everything else). |

Retention per resolution:

| Resolution | Kept | Created from |
|---|---|---|
| raw (15s) | 15 days | — |
| 5 minutes | 90 days | raw blocks older than about 40 hours |
| 1 hour | 5 years | 5m blocks older than about 10 days |

What this means in Grafana:

- `--query.auto-downsampling` lets query choose the coarsest resolution that
  still fits the graph's step. A week view reads 5m data and a year view reads
  1h data, so wide ranges stay fast.
- After 15 days the raw points are gone, so zooming into a day from last
  month shows 5m points. After 90 days you only get 1h points.
- The 5m and 1h blocks store min, max, sum, count and counter per
  window. `rate()`, `avg_over_time()`, `max_over_time()` and the others still
  work on them.
- Keep `[$__rate_interval]` (not a fixed `[1m]`) in queries. On 5m or 1h data
  a short window has fewer than two points and returns nothing.

The bucket is only files, so moving it to S3 or MinIO later only changes
`objstore` in `services/thanos/default.nix`. Then copy the existing blocks
over.

### Logs: Loki (nix-loki)

- Filesystem storage under `/var/lib/loki`, TSDB index v13, one index per
  day.
- `retention_period = 720h` (30 days). The compactor deletes older chunks,
  checking every 10 minutes with a 2h delete delay.
- `reject_old_samples_max_age = 168h`: lines up to a week old are still
  accepted, which covers a long agent backlog.
- Ingestion is limited to 10 MB/s (burst 20 MB/s), so a container that
  spams the log cannot overload Loki.

## Timestamps, outages and backlog

Every sample and every log line keeps the timestamp from when it was taken
on the agent, **not** when it reached Thanos or Loki.

- **Metrics**: when Thanos is unreachable, Alloy keeps samples in its
  write-ahead log, up to 8h (`max_keepalive_time`). Once Thanos is back it
  sends the backlog. Thanos Receive accepts samples up to 8h old
  (`--tsdb.out-of-order.time-window=8h`), and compact merges the resulting
  overlapping blocks (`--compact.enable-vertical-compaction`). Samples more
  than 5 minutes in the future (clock skew) are rejected.
- **Logs**: Alloy stores its position in each journal, so after an outage it
  continues from where it stopped. On first start (no stored position) it
  reads back at most 12h (`max_age`).
- Outages longer than 8h lose the metrics beyond those 8h. Logs are kept
  as long as the journal still has them and they are less than a week old.

## Probes

Probes are generated, so there is nothing to keep in sync by hand.

| Prober | Targets | Module | Generated from |
|---|---|---|---|
| homelab | every container with a `service`, `autoStart = true` and `port != 0`: `<ip>:<port>` | `tcp_connect` | `inventory/nodes.nix` |
| homelab | every nginx vhost ending in `.<domain>` (no wildcards) | `http_up` | `containers.nix-nginx.config.services.nginx.virtualHosts` |
| hetzner-vps-01 | the same vhosts minus those that contain `deny all;` (internal only) | `http_up` | `publicVhosts` in `flake/hosts.nix` |

Modules (`modules/nixos/alloy-agent.nix`):

- `tcp_connect`: the port accepts a TCP connection within 5s.
- `http_up`: an HTTPS request answers within 10s with a status that is
  **not 5xx**. Redirects are not followed, and 2xx, 3xx, 400, 401, 403, 404
  and 405 count as up. A login page or a redirect to Keycloak therefore
  means "the service is there". A 502/503/504 from nginx (backend down) means
  down. The TLS certificate is checked too, and its expiry is in
  `probe_ssl_earliest_cert_expiry`.

The same vhost probed from both sides tells you where a problem is:

- down from `homelab` → the service or nginx itself is down;
- down only from `hetzner-vps-01` → the path from outside is broken (DNS,
  VPS, WireGuard, router).

## Grafana: dashboards

`https://grafana.<domain>` goes straight to Keycloak (OIDC, configured in
`services/grafana/default.nix`, nothing to click in the UI). Roles are set
on every login: group `grafana-admin` → Admin and server admin,
`grafana-editor` → Editor, everyone else → Viewer. Grafana holds no state
of its own worth keeping, since datasources, dashboards, alerts and the
contact point are all provisioned. If its database is ever in the way,
delete it (`/var/lib/grafana` in nix-grafana) and restart. The local login
(`admin`, `GRAFANA_ADMIN_PASSWORD`) stays reachable at
`/login?disableAutoLogin=true` for when Keycloak is down.

Everything provisioned is in the folder **Homelab**:

- **Homelab** (`uid homelab`), the overview, in tabs:
  - **Services**: what runs and what doesn't, and why.
    - Counters: down, degraded, running, open problems.
    - One tile per container that starts at boot: *running*, *degraded*
      (failed units inside) or *DOWN* (container not active, or its port
      doesn't answer).
    - **What is wrong, and why**: one row per problem with service, problem
      and detail. Covers a container that is failed or inactive (with its
      state), the failed unit inside a container, a port that doesn't answer
      (with the address), a website that is down (seen from inside or from
      the VPS), and failed units on the host or VPS.
    - History of every service (state timeline), so you can see when it
      was down.
    - **Space per service**: system disk (container root on the NVMe) and
      HDD pool (its datasets, with snapshots).
    - Logs, warnings and worse.

    The `service` variable at the top filters every per-service panel in
    all tabs. "All" also includes series without a service, such as the
    https probes, which are named after the host.
  - **Storage**: filesystems, ZFS pools (usable space after parity, not
    `zpool list`'s raw size), space per service over time, every pool
    dataset.
  - **Disks (SMART)**:
    - Per disk: model, serial, firmware, health, temperature, hours powered
      on, damage counters, NVMe wear.
    - Damage counters as a matrix: disk × reallocated, pending and
      uncorrectable sectors, CRC errors, …
    - The damage counters and temperatures over time, NVMe health.
    - **every** SMART attribute, with value, worst, threshold, raw and the
      margin to the threshold.
    - Error and self-test logs.
  - **Host**: temperature, uptime, load, failed units, CPU, memory,
    temperatures, disk IO, network.
  - **Containers**: CPU, memory and disk IO per container.
  - **Probes**: every probe over time, response times, days left on each
    certificate.
  - **Logs**: log volume per machine, errors everywhere.

  The dashboard uses Grafana's schema v2 (`dashboard.grafana.app/v2beta1`),
  which is needed for tabs. `services/grafana/dashboards.nix` has small
  helpers (`panel`, `stat`, `q`, `at`) that generate it.
- **Node Exporter Full** (grafana.com 1860, revision 46): every node metric
  of one machine. Pick the machine with the job and host variables at the
  top.

Provisioned dashboards cannot be saved from the UI. Either copy one
("Save as") into another folder to experiment, or change
`services/grafana/dashboards.nix`. For a JSON exported from the UI, add it to
the `linkFarm` at the bottom of that file, as is done for `node-full.json`.

Ad-hoc digging goes through **Explore** with the Thanos datasource (PromQL)
or the Loki datasource (LogQL).

## Grafana: alerts

Rules are in `services/grafana/alerts.nix` and show up under Alerting → Alert
rules, folder Homelab. Every rule is an instant PromQL query that is
evaluated every minute. Each returned series is its own alert instance, so
one rule fires separately per disk, container or vhost. "No data" counts as
OK.

| uid | Fires when | For | Severity |
|---|---|---|---|
| `probe-down` | a probe fails (`probe_success == 0`) | 5m | critical |
| `container-down` | a container with `autoStart` is not `active` on the host | 3m | critical |
| `unit-failed` | a systemd unit on the host or VPS is `failed` | 2m | warning |
| `container-unit-failed` | a unit inside a container is `failed` | 2m | warning |
| `agent-silent` | no `node_uname_info` from `homelab` or `hetzner-vps-01` for 10m | 5m | warning |
| `cert-expiry` | a probed TLS certificate expires in under 14 days | 1h | warning |
| `disk-full` | a filesystem is over 90% full | 15m | warning |
| `memory-high` | memory is over 90% used | 15m | warning |
| `temperature-high` | a hwmon sensor is above 85°C | 10m | critical |
| `disk-temperature-high` | a disk is above 55°C | 10m | warning |
| `smart-failing` | SMART health check failed | 0s | critical |
| `zpool-degraded` | a ZFS pool is not ONLINE | 0s | critical |
| `smart-sectors-rising` | reallocated / pending / uncorrectable sectors (5, 196, 197, 198) rose within 24h | 0s | critical |
| `smart-errors-rising` | reported uncorrectable, command timeouts or CRC errors (187, 188, 199) rose within 24h | 0s | warning |
| `smart-near-threshold` | a normalized SMART value is less than 10 above its failure threshold | 1h | warning |
| `smart-selftest-failed` | a SMART self-test failed within 24h | 0s | critical |
| `smart-errorlog-rising` | new entries in the ATA error log within 24h | 0s | warning |
| `nvme-media-errors` | NVMe media errors rose within 24h | 0s | critical |
| `nvme-critical-warning` | NVMe critical warning set | 0s | critical |
| `nvme-wear` | NVMe used more than 80% of its rated endurance | 1h | warning |
| `nvme-spare-low` | NVMe spare less than 10 points above its threshold | 1h | warning |
| `smart-not-read` | no SMART data for 30 minutes | 0s | warning |

The "rose within 24h" rules stay active for a day after each increase and
then clear by themselves. A disk that keeps getting worse keeps them firing.

### Notifications

Alerts go to **ntfy** on the VPS (`https://notify.monitor.<domain>`, topic
`homelab`). It runs there so notifications still arrive when the homelab is
down. Details are in [Notifications and outside checks](#notifications-and-outside-checks-vps).

- Contact point `ntfy` (a webhook, provisioned in
  `services/grafana/default.nix`) is the default policy's only receiver.
  Alerts are grouped by folder and alert name and repeated every 4h while
  they fire. A message is sent when they resolve.
- ntfy's inline template (`?tpl=yes&t={{.title}}&m={{.message}}`) turns
  Grafana's JSON into a title and a message.
- Grafana authenticates with the token of the ntfy user `alerts`. That user
  may only publish to `homelab`. The token is `NTFY_TOKEN` in
  `services/grafana/secrets.enc.yaml`.

## Notifications and outside checks (VPS)

`hosts/hetzner-vps-01/notify.nix`:

```
 internet ──443──▶ Traefik (Let's Encrypt) ──▶ ntfy 127.0.0.1:2586 ──▶ phone app
                   notify.monitor.<domain>                ▲          ▲
 Grafana (homelab) ── webhook, topic homelab ─────┘          │
 Gatus (VPS) ── checks every 30s/1m, alerts locally ─────────┘
```

- **One subdomain for the VPS.** `monitor.<domain>` and `*.monitor.<domain>`
  point to the VPS, so a new name there needs no DNS change:

  | Name | Goes to |
  |---|---|
  | `notify.monitor.<domain>` | ntfy |
  | `status.monitor.<domain>` | Gatus status page (basic auth, same login as the ntfy admin) |
  | `monitor.<domain>` | redirect to `status.` |

- **Traefik** terminates TLS with one Let's Encrypt certificate per name
  (HTTP-01 on port 80, stored in `/var/lib/traefik/acme.json`). It redirects
  http to https and proxies to ntfy and Gatus. Its access log goes to the
  journal and from there to Loki (`instance="hetzner-vps-01"`,
  `unit="traefik.service"`). At home, AdGuard keeps the public answer for
  `monitor.<domain>` and `*.monitor.<domain>` instead of the `*.<domain>` →
  nix-nginx rewrite (`services/adguardhome/default.nix`).
- **ntfy** allows nothing without an account (`auth-default-access =
  deny-all`, no sign-up). Users, the access rule and the token are
  provisioned from sops:

  | ntfy user | Role | Used by |
  |---|---|---|
  | `hajoha` (`adminUser`) | admin | phone app: subscribe to `homelab`. Also the status page login |
  | `alerts` | user, write-only on `homelab` | Grafana and Gatus, with the token `tk_…` |

  Messages are cached for 72h for clients that were offline.
  The web app is disabled (`web-root = "disable"`). Only the phone app and
  the API answer.
- **fail2ban** (jail `traefik-auth`) reads Traefik's access log from the
  journal. 10 failed logins (HTTP 401) within 10 minutes, on either
  `notify.` or `status.`, ban that address for http/https. The ban time
  grows the same way as for ssh. SSH is not affected, and WireGuard
  addresses are never banned. A phone with an old password keeps failing
  and bans itself, so update the app after changing the password.

  ```bash
  fail2ban-client status traefik-auth
  fail2ban-client set traefik-auth unbanip <ip>
  ```
- **Gatus** is the outside ping check. It runs on the VPS, alerts through the
  local ntfy (not through Traefik, so a broken certificate still gets
  reported), and needs nothing at home to work:

  | Group | Check | Interval |
  |---|---|---|
  | notify | `https://notify.monitor.<domain>/v1/health` answers `healthy`, certificate valid > 7 days | 1m |
  | home | ping to home-openwrt over WireGuard | 30s |
  | home | tcp to nix-loki :3100 and nix-thanos :19291 over WireGuard | 30s |
  | public | every public vhost (`publicVhosts`): status < 500, certificate valid > 7 days | 1m |

  An alert goes out after 3 failed checks and a resolved message after 2
  good ones. If the `home` checks fail, Grafana's own alerts may not
  arrive (and Thanos misses the VPS metrics), so this is the alert that
  says "the homelab itself is gone".

  The status page with history is `https://status.monitor.<domain>`.

The homelab Alloy also probes `https://notify.monitor.<domain>/v1/health` (probe
`notify`), so `probe-down` fires in Grafana when the VPS or ntfy is down.
That alert cannot arrive through ntfy, but it is visible in Grafana.

### Setup (once)

1. DNS: `monitor.<domain>` **and** `*.monitor.<domain>` to the VPS (A/AAAA,
   or CNAME to its hostname). A record for `monitor.` alone does not cover
   the names below it. Ports 80 and 443 must be reachable.
2. Secrets on the VPS, `sops hosts/hetzner-vps-01/secrets.enc.yaml`:

   ```yaml
   ntfy:
     admin-hash: $2a$10$…     # nix shell nixpkgs#ntfy-sh -c ntfy user hash  (your password)
     alerts-hash: $2a$10$…    # same, with a random password nobody needs
     alerts-token: tk_…       # echo "tk_$(tr -dc a-z0-9 </dev/urandom | head -c 29)"
   ```

3. The same token for Grafana, `sops services/grafana/secrets.enc.yaml`:
   `NTFY_TOKEN: tk_…`.
4. Deploy the VPS first, then the homelab. sops-nix fails the activation
   while a secret it expects is missing, so add the keys before deploying.
5. Phone: ntfy app → add server `https://notify.monitor.<domain>`, log in as the
   admin user, subscribe to `homelab`. Test it:

   ```bash
   curl -H "Authorization: Bearer tk_…" -d "test" https://notify.monitor.<domain>/homelab
   ```

To get a notification from a script anywhere, use the same `curl` (or a
separate ntfy user with its own token and topic).

## Network paths

Alloy pushes and Grafana pulls, so every connection goes out from the agent
or from Grafana:

| From | To | Port | Path |
|---|---|---|---|
| homelab host (management `10.60.0.4`) | nix-loki `10.60.1.27` | 3100 | through the router (management → service VLAN). The host cannot reach its containers over the macvlans |
| homelab host | nix-thanos `10.60.1.28` | 19291 | same |
| homelab host | every container `<ip>:<port>` (tcp probes) | various | same |
| homelab host | the vhosts (https probes) | 443 | via nix-nginx, as resolved by DNS |
| hetzner-vps-01 (WireGuard `10.60.71.x`) | nix-loki, nix-thanos | 3100, 19291 | WireGuard to home-openwrt, which forwards to the service VLAN (`routes` in `wireguard-peers.json`) |
| nix-grafana | nix-loki :3100, nix-thanos :10902 | | service VLAN |
| nix-grafana | `notify.monitor.<domain>` (VPS) | 443 | internet |
| Gatus (VPS) | home-openwrt (ping), nix-loki :3100, nix-thanos :19291 | | WireGuard |

nix-loki has no default gateway (`gateway = false`). Static routes for
`10.60.0.0/24` (management) and `10.60.71.0/24` (WireGuard) via `10.60.1.1`
let it answer the host and the VPS. nix-thanos uses the default gateway.

The router firewall has to allow these flows. If `agent-silent` fires right
after a deploy, check that first.

## Operating it

### Alloy

```bash
# on the host (or the VPS)
systemctl status alloy
journalctl -u alloy -f                    # only warnings and errors (level warn)
ls /etc/alloy/                            # base.alloy, homelab.alloy

# pipeline UI: every component, its health, targets, last error
ssh -L 12345:127.0.0.1:12345 root@10.60.0.4      # then http://localhost:12345
```

The UI's graph view shows, for example, whether a container's
`loki.source.journal` is healthy and whether `prometheus.remote_write`
is behind.

### Thanos

```bash
journalctl -M nix-thanos -u thanos-receive -u thanos-compact -f
nixos-container root-login nix-thanos

# inside nix-thanos (curl: nix shell nixpkgs#curl if missing)
curl -s localhost:10902/-/ready
thanos tools bucket ls --objstore.config-file=<(echo '{type: FILESYSTEM, config: {directory: /var/lib/thanos/bucket}}') -o wide
du -sh /var/lib/thanos/bucket /var/lib/thanos-receive
curl -s 127.0.0.1:10912/metrics | grep thanos_compact_halted   # 1 = compact stopped on an error
```

The Thanos Query UI is at `http://10.60.1.28:10902` from the service VLAN or
through an ssh tunnel. Its "Stores" page lists receive and store with the
time range each one covers.

### Loki

```bash
journalctl -M nix-loki -u loki -f
du -sh /var/lib/nixos-containers/nix-loki/var/lib/loki/*
```

### Useful queries

PromQL (Thanos):

```promql
probe_success == 0                                        # what is down right now, and from where
sum by (machine) (rate(container_cpu_usage_seconds_total{machine!=""}[$__rate_interval]))
topk(5, container_memory_working_set_bytes{machine!=""})
node_systemd_unit_state{state="failed"} == 1
homelab_container_unit_failed
(probe_ssl_earliest_cert_expiry - time()) / 86400         # days until certs expire
smartctl_device_temperature{temperature_type="current"}
count by (__name__) ({__name__=~".+"})                    # series per metric (cardinality)
```

LogQL (Loki):

```logql
{instance="nix-paperless"}                               # everything from one container
{instance="nix-immich", unit="immich-server.service"} |= "error"
{job="systemd-journal", level=~"emerg|alert|crit|error"}
sum by (instance) (count_over_time({job="systemd-journal"}[5m]))   # who logs the most
```

## Extending it

### A new container

Nothing to do. Once it is in `inventory/nodes.nix` and deployed, its journal
is read, its cgroup shows up in cAdvisor, it gets a tcp probe on `port`
(when `port != 0` and `autoStart`), and `container-down` covers it. A new nginx
vhost gets https probes, from the VPS as well unless it has `deny all;`.

### An extra probe

Add it to `homelab.alloy.probes` in `hosts/homelab/monitoring.nix`:

```nix
homelab.alloy.probes.router-ui = {
  address = "https://10.60.0.1";    # URL for http_up, host:port for tcp_connect
  module = "http_up";
};
```

### Scraping a Prometheus endpoint of a service

Many services can export metrics (`/metrics`). Add an Alloy file on the host
and open the port in the container's `tcp` in `nodes.nix`. The host reaches
the container through the router, like the probes:

```nix
# hosts/homelab/monitoring.nix
environment.etc."alloy/paperless.alloy".text = ''
  prometheus.scrape "paperless" {
    targets = [{ "__address__" = "${nodes.nix-paperless.ip}:9100", "instance" = "nix-paperless", "job" = "paperless" }]
    scrape_interval = "30s"
    forward_to      = [prometheus.remote_write.default.receiver]
  }
'';
```

Keep the label cardinality low: no user IDs, request paths or similar as
labels.

### A metric from a script

Write `*.prom` files (Prometheus text format) into
`/var/lib/homelab-metrics/` on the host. The node exporter picks them up
on every scrape. Write to a temporary file and `mv` it into place, as
`homelab-container-units` does, so a scrape never sees half a file.

### An alert rule

Add a `(rule { … })` to a group in `services/grafana/alerts.nix`. Write the
query so that it returns a value `> 0` (or set `threshold`) only when
something is wrong, and nothing otherwise:

```nix
(rule {
  uid = "borg-stale";                     # stable, unique
  title = "Backup older than a day";
  expr = ''time() - node_systemd_timer_last_trigger_seconds{name="borgmatic.timer"} > 86400'';
  summary = "borgmatic has not run for {{ $values.A.Value | humanizeDuration }}";
  for = "1h";
})
```

### Another machine

Import `modules/nixos/alloy-agent.nix`, set `homelab.alloy` (`enable`,
`instance`, `lokiUrl`, `remoteWriteUrl`, as in
`hosts/hetzner-vps-01/monitoring.nix`), make sure the machine can reach
nix-loki:3100 and nix-thanos:19291, and add its `instance` to `agents` in
`services/grafana/alerts.nix` so `agent-silent` covers it.

## Troubleshooting

**`agent-silent` fires / no metrics from a machine.**
`journalctl -u alloy` on that machine. Connection refused or a timeout to
`:19291` means a network path problem (router firewall, WireGuard route; see
[Network paths](#network-paths)). HTTP 4xx from receive usually means
samples outside the time window (clock skew, or a backlog older than 8h).

**A container's logs are missing.** Check that
`/var/lib/nixos-containers/<name>/var/log/journal/<machine-id>/` exists and
grows. journald inside writes there persistently once the directory exists,
and tmpfiles creates it. In the Alloy UI, look at
`loki.source.journal.<name>`, where dashes become underscores.

**No per-container CPU/memory (no `machine` label).** cAdvisor finds the
containers as `/machine.slice/container@<name>.service`. Compare with
`systemd-cgls /machine.slice` on the host. If the path differs, adjust the
regex in the `prometheus.relabel "machines"` block in
`hosts/homelab/monitoring.nix`.

**A tcp probe is always down.** Either the inventory `port` is not open in
the container's firewall (`tcp`), or the router blocks management →
service VLAN for that port. Example: nix-opencloud has `port = 9200` but
opens only `9100`.

**Graphs older than two weeks look coarse or are empty with small
windows.** This is expected, because only 5m/1h data exists there. Use
`$__rate_interval` and see
[Storage and retention](#storage-and-retention).

**Panels and alert rules fail with "plugin not registered".** Since
Grafana 13, the Prometheus and Loki datasources are separate plugins. They
come from nixpkgs (`pkgs.grafanaPlugins.prometheus` / `.loki`, set in
`services/grafana/default.nix` as `declarativePlugins`) and are updated
together with Grafana by `nix flake update`.

**Thanos compact stopped.** `thanos_compact_halted 1` on `:10912/metrics`
and an error in `journalctl -M nix-thanos -u thanos-compact`. Without
compact there is no downsampling and no retention, so the bucket only grows.
Fix the cause (often an overlapping or broken block, which `thanos tools
bucket verify` finds) and restart `thanos-compact`.

**The same log lines appear twice right after the switch to this setup.**
This happens once. The first start reads back 12h of journal that the old
promtail/alloy had already sent.

## Known gaps and to-dos

- **Home Assistant** history stays in its recorder in nix-postgres and is
  not in Thanos. HA keeps 5-minute statistics (deleted together with the raw
  states after `purge_keep_days`) and hourly long-term statistics (kept
  forever). Shrinking it later is mainly `recorder.purge_keep_days`.
- **Router firewall and OpenWrt forwarding** for the flows in
  [Network paths](#network-paths) are configured outside this repo.
- **cAdvisor on systemd-nspawn cgroups** was set up from the cgroup layout
  but has not been checked against live data.
- **Out-of-order ingestion** in Thanos Receive is marked experimental
  upstream.
- **One Thanos, one disk.** There is no replication. The bucket and Loki's
  chunks live in their container roots on the NVMe, and borgmatic backs
  those up with `/var/lib/nixos-containers`. A restore therefore brings the
  data back as of the last backup.
- The autossh tunnel `dsp25-main-influx` in nix-grafana belongs to an external
  InfluxDB (dsp25), not to the homelab monitoring.
