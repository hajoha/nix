# How the homelab host works

- Each inventory node with a `service` becomes `containers.<node>` (systemd-nspawn).
  Containers share the host's `/nix/store` (read-only): one store, one GC,
  one deploy for everything.
- Container root = plain directory `/var/lib/nixos-containers/<node>` on the
  NVMe (fast, no snapshots; borgmatic backs it up). Large data
  (`hosts/homelab/data-volumes.nix`: postgres, immich, arr, opencloud) stays
  on the HDD pool as `<pool>/containers/<node>/<name>`, mounted inside the
  root; sanoid snapshots those (hourly 24, daily 14, monthly 3).
- The pool is encrypted and unlocked by hand after every boot; until then
  the containers with data volumes (and those that need them) wait:
  `zfs load-key threetbpool && zfs mount -a`.
- Start order: inside a container, its services start only once every
  interface is up and has its address (`homelab-network-ready`). Between
  containers, a node starts after the nodes it needs (`needs` in
  `nodes.nix`; `db = true` → nix-postgres, `sso = true` → nix-keycloak,
  nix-nginx, nix-adguard). A container counts as up once its boot has
  finished, i.e. its services run. Everything else starts right away. So:
  network → postgres (after the pool) → keycloak → the services using them.
- Networking: the host has one VLAN interface per network (`service`, `iot`,
  `dmz`, `wireguard`, ids in `params.nix`) without an address. Every container
  gets a macvlan on each VLAN it uses, renamed inside to the VLAN name, and its
  inventory IP. The router sees each container as its own machine. (The host itself cannot talk to its containers over macvlan;
  use `nixos-container root-login <node>` or go via the router.)
  A `root-login` shell that is still open while its container restarts
  keeps the old network namespace and macvlan alive. The new macvlan has
  the same MAC and cannot come up ("Address already in use"), and the
  container would wait 5 minutes for its address. Before every container
  start, the host therefore kills shells whose container instance is gone
  (`homelab-kill-stale-container-shells`, `modules/nixos/homelab-host.nix`).
- Secrets: every container has its own ssh host key
  (`/var/lib/homelab/keys/<node>`, bind-mounted read-only) as its sops
  identity; its age recipient is the node's `age` in `nodes.nix`. See
  [Container keys](secrets.md#container-keys).

```bash
nixos-container list
nixos-container root-login nix-paperless
systemctl status container@nix-paperless
journalctl -M nix-paperless -u paperless-web -f
machinectl                                # running containers, IPs
```

Inside a service, use `config.homelab` instead of hard-coding addresses:

```nix
{ config, ... }:
let
  inherit (config.homelab) nodes sso;
in
{
  # nodes.nix-postgres.ip / .port    raw address
  # nodes.nix-hedgedoc.addr          "http://10.60.1.23:3005"
  # nodes.nix-hedgedoc.fqdn / .url   "hedgedoc.hackler.io" / "https://…"
  # sso.issuer                       Keycloak realm issuer URL
}
```

