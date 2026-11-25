# Services (containers)

Every row is an entry in `inventory/nodes.nix`. That file is the source of
truth, so if this table and the file disagree, the file is right. The
configuration of each container is in `services/<service>/default.nix`.
The service directory is the node name without `nix-`, unless the table
says otherwise.

All IPs are on the service VLAN `10.60.1.0/24`. The public name is
`<sub or hostname>.<domain>`, if nix-nginx has a vhost for it.

| Node | IP | Port | Service dir | DB | SSO | Notes |
|---|---|---|---|---|---|---|
| **Edge and infrastructure** |
| nix-nginx | .17 | 443 | nginx | | | reverse proxy and TLS, default route via the DMZ (`10.60.50.17`) |
| nix-adguard | .16 | 3000 | adguardhome | | | DNS for the containers (53 tcp/udp) |
| nix-postgres | .20 | 5432 | postgres | | | databases for every `db = true` node |
| nix-keycloak | .22 | 8080 | keycloak | yes | | SSO (`sso.<domain>`), issuer for every `sso = true` node |
| nix-headscale | .30 | 8080 | headscale | | yes | Tailscale control server, DERP/STUN 3478/udp |
| nix-hooks | .18 | 9000 | hooks | | | GitHub webhooks → host CI ([deploy.md](deploy.md)) |
| **Observability** ([monitoring.md](monitoring.md)) |
| nix-loki | .27 | 3100 | loki | | | logs, 30 days, no default gateway |
| nix-thanos | .28 | 10902 | thanos | | | metrics, remote write on 19291 |
| nix-grafana | .25 | 3000 | grafana | | yes | dashboards and alerts |
| **Apps** |
| nix-hedgedoc | .23 | 3005 | hedgedoc | yes | yes | |
| nix-listmonk | .24 | 9000 | listmonk | yes | | newsletter (`newsletter.<domain>`) |
| nix-paperless | .32 | 28981 | paperless | yes | yes | |
| nix-immich | .35 | 2283 | immich | yes | yes | photos (`photo.<domain>`), data on the HDD pool |
| nix-commafeed | .36 | 8082 | commafeed | yes | | RSS (`rss.<domain>`) |
| nix-sure | .37 | 3000 | sure | yes | yes | finance |
| nix-opencloud | .14 | 9200 | opencloud | | yes | files, data on the HDD pool, Collabora on 9980 |
| nix-tranquil | .39 | 3000 | tranquil | yes | yes | ATProto PDS (`pds.<domain>`), `autoStart = false` |
| nix-arr | .31 | 8096 | nixarr | | yes | Jellyfin and the *arr stack, data on the HDD pool |
| nix-flathunter | .40 | 8080 | flathunter | | | outbound crawler, `autoStart = false` |
| **Smart home and network** |
| nix-homeassistant | .33 | 8123 | hass | yes | yes | also on the IoT VLAN (`10.60.60.33`), IPv6, Music Assistant |
| nix-unifi-controller | .34 | 8443 | unifi-controller | | | UniFi controller, device inform on 8080 |
| **Retired** (no container, IP reserved) |
| nix-zitadel | .21 | | | | | replaced by Keycloak |
| nix-influx | .26 | | | | | replaced by nix-thanos |
| nix-build | .15 | | | | | the host builds for itself |

Columns:

- **DB**: nix-postgres creates a database and user named after the service
  and syncs the password from `services/<service>/postgres.enc.yaml`. The
  container starts after nix-postgres.
- **SSO**: logs in through Keycloak and starts after nix-keycloak,
  nix-nginx and nix-adguard.

Other machines in this repo:

| Host | What | Config |
|---|---|---|
| `homelab` | the server, NixOS on bare metal, runs all of the above | `hosts/homelab/`, [homelab-host.md](homelab-host.md) |
| `hetzner-vps-01` | WireGuard hub (tunnel to home-openwrt), ssh with fail2ban, `monitor.<domain>`: ntfy (`notify.`), Gatus status page (`status.`) behind Traefik; probes from outside | `hosts/hetzner-vps-01/` |
| `nixmaschine` | desktop (NixOS + home-manager) | `hosts/nixmaschine/` |
| `haa` | work laptop, standalone home-manager | `hosts/nixarbeitsmaschine/` |
| `pi3-sendspin` | Raspberry Pi 3, Sendspin player ("Wohnzimmer") | `hosts/pi3-sendspin/` |
