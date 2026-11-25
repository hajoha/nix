# home-nix

NixOS + home-manager config for the homelab server (`homelab`: NixOS on bare
metal, every service a NixOS container), the desktop (`nixmaschine`), the
work laptop (`haa`, standalone home-manager), a Hetzner VPS and a Raspberry Pi.

## Layout

```
flake.nix               inputs + wiring only
flake/
  homelab.nix           the homelab host + its deploy-rs node
  hosts.nix             nixmaschine, hetzner-vps-01, pi3-sendspin, homeConfigurations.haa
inventory/
  nodes.nix             ONE entry per container: ip, port, names, firewall, db, age key
  keys.nix              admin + host age keys
  default.nix           derives networking + the homelab module config from nodes.nix
  sops.nix              generates .sops.yaml
hosts/homelab/
  params.nix            facts about the box: hostId, NIC, VLAN ids, pool, GPU, radio
  configuration.nix     host: boot, ZFS, nix, packages
  network.nix           host management address
  containers.nix        per-container extras: devices, capabilities, data binds
  data-volumes.nix      container data that lives on the HDD pool
  backup.nix            borgmatic to backup-01 (ZFS snapshots)
  container-keys.nix    installs container ssh keys from container-keys.enc.json
  ci.nix, ci/           GitHub webhooks: PR preview, deploy with health check + rollback
  monitoring.nix        the one Alloy: host + all container journals/metrics, probes
  secrets.enc.yaml      host secrets (borg passphrase)
  disko.nix             NVMe layout
modules/
  nixos/homelab-host.nix   inventory -> containers.<name>, datasets, keys, VLANs
  nixos/container-base.nix base for every container
  nixos/homelab.nix        typed inventory (config.homelab), ssh-client, vm
  nixos/alloy-agent.nix    Alloy agent (journal -> Loki, node metrics/probes -> Thanos)
  home/profiles/        base.nix (every machine), desktop.nix (niri/noctalia desktop)
  home/…                browser, mail, desktop, editor, programs
services/<name>/        one per container: default.nix + its *.enc.yaml secrets
hosts/<name>/           other machines (hardware, disko, home.nix)
pkgs/                   local packages
secrets/                secrets not tied to a service
docs/                   documentation (see below)
```

## Documentation

| | |
|---|---|
| [How the homelab host works](docs/homelab-host.md) | containers, storage, start order, networking |
| [Services](docs/services.md) | every container: IP, port, database, SSO |
| [Add a new service](docs/add-service.md) | inventory entry, key, secrets, vhost |
| [Secrets](docs/secrets.md) | sops-nix, container keys |
| [Deploy and CI](docs/deploy.md) | deploy-rs, PR previews, auto-deploy with rollback, updates |
| [(Re)install](docs/install.md) | installing the host, unlocking the pool after a reboot |
| [Monitoring](docs/monitoring.md) | Alloy, Loki, Thanos, Grafana: logs, metrics, probes, alerts |

## Quick reference

```bash
nix develop                         # sops, age, ssh-to-age, deploy-rs
deploy .#homelab                    # host + all containers
nix flake check                     # also fails if .sops.yaml is stale
nixos-container root-login nix-paperless
journalctl -M nix-paperless -u paperless-web -f
zfs load-key threetbpool && zfs mount -a     # after every reboot
```
