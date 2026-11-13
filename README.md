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
  disko.nix             NVMe layout
modules/
  nixos/homelab-host.nix   inventory -> containers.<name>, datasets, keys, VLANs
  nixos/container-base.nix base for every container
  nixos/homelab.nix        typed inventory (config.homelab), ssh-client, vm
  home/profiles/        base.nix (every machine), desktop.nix (niri/noctalia desktop)
  home/…                browser, mail, desktop, editor, programs
services/<name>/        one per container: default.nix + its *.enc.yaml secrets
hosts/<name>/           other machines (hardware, disko, home.nix)
pkgs/                   local packages
secrets/                secrets not tied to a service
```

## How the homelab host works

- Each inventory node with a `service` becomes `containers.<node>` (systemd-nspawn).
  Containers share the host's `/nix/store` (read-only): one store, one GC,
  one deploy for everything.
- Container root = plain directory `/var/lib/nixos-containers/<node>` on the
  NVMe (fast, no snapshots; borgmatic backs it up). Large data
  (`hosts/homelab/data-volumes.nix`: postgres, immich, arr, opencloud) stays
  on the HDD pool as `<pool>/containers/<node>/<name>`, mounted inside the
  root; sanoid snapshots those (hourly 24, daily 14, monthly 3).
- The pool is encrypted and unlocked by hand after every boot; until then
  the containers with data volumes refuse to start:
  `zfs load-key threetbpool && zfs mount -a && systemctl start machines.target`.
- Networking: the host has one VLAN interface per network (`service`, `iot`,
  `dmz`, `wireguard`, ids in `params.nix`) without an address. Every container
  gets a macvlan on each VLAN it uses, renamed inside to the VLAN name, and its
  inventory IP. The router sees each container as its own machine. (The host itself cannot talk to its containers over macvlan;
  use `nixos-container root-login <node>` or go via the router.)
- Secrets: every container has its own ssh host key
  (`/var/lib/homelab/keys/<node>`, bind-mounted read-only), generated on
  first start; its age recipient is the
  node's `age` in `nodes.nix` (`homelab-age-keys` prints them all).

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

## Add a new service

1. Add an entry to `inventory/nodes.nix` (`ip`, `hostname`, `port`, `tcp`, …).
   Set `db = true;` if it needs a Postgres database.
2. Create `services/<name>/default.nix` (the directory defaults to the node
   name without `nix-`; override with `service = "…";`).
3. `deploy .#homelab`. The container starts with a fresh ssh host key; add its
   age key to the node:
   `ssh-to-age < /var/lib/homelab/keys/<node>/ssh_host_ed25519_key.pub` →
   `age = "age1…";`
4. `nix run .#sops-config`, create the secrets (see below; with `db = true`
   also `services/<name>/postgres.enc.yaml` with a `password:` key), deploy
   again.
5. If it should be reachable from outside, add a vhost in
   `services/nginx/default.nix` (`vhost` / `proxy` helpers).

Devices, extra capabilities or bind mounts for one container go into
`hosts/homelab/containers.nix` as plain `containers.<node>.*` options.

## Deploy

```bash
nix develop                         # sops, age, ssh-to-age, deploy-rs
deploy .#homelab                    # host + all containers
deploy .#homelab --dry-activate
nix build .#containers.nix-paperless  # build/eval a single container

sudo nixos-rebuild switch --flake .#nixmaschine --accept-flake-config
home-manager switch --flake .#haa --accept-flake-config
```

`--accept-flake-config` makes nix use the binary caches from `nixConfig` in
`flake.nix` (tranquil, noctalia); without it those packages are built from
source.

Evaluating the homelab host with all containers needs ~16 GB RAM. If the
machine you deploy from has less, build on the box itself (no git there):

```bash
rsync -a --delete --exclude '/result*' --exclude '/homelab*' --exclude '/.git' --exclude '/.direnv' \
  ./ root@10.60.0.4:/root/home-nix/
ssh root@10.60.0.4 nixos-rebuild switch --accept-flake-config --flake path:/root/home-nix#homelab
```

## Secrets (sops-nix)

`.sops.yaml` is generated, so don't edit it by hand. A service's
`services/<svc>/*.enc.yaml` can be decrypted by that node's `age` key, by its
`sopsReaders`, and by the admin keys; `postgres.enc.yaml` also by
`nix-postgres`. Host secrets (`hosts/<host>/*.enc.yaml`, e.g. the borg
passphrase in `hosts/homelab/secrets.enc.yaml`) use that host's key in
`inventory/keys.nix`.

```bash
nix run .#sops-config                         # after changing keys in inventory/
sops services/hedgedoc/secrets.enc.yaml       # create / edit
sops updatekeys services/hedgedoc/secrets.enc.yaml   # after recipients changed
nix flake check                               # also fails if .sops.yaml is stale
```

## (Re)installing the homelab host

Boot a NixOS installer from USB **in UEFI mode** on the box, ssh into it and
copy the repo over (`rsync … ./ root@<live-ip>:/root/home-nix/`, without
`.git`). Then:

```bash
export NIX_CONFIG="experimental-features = nix-command flakes"
F=path:/root/home-nix#homelab
nix run github:nix-community/disko/latest -- --mode destroy,format,mount --flake $F
nixos-install --flake $F --no-root-passwd --no-channel-copy --option accept-flake-config true
efibootmgr        # "Linux Boot Manager" must be there and first
```

- disko only touches `params.rootDisk`; the HDD pool is not part of it.
- The board (Fujitsu D3417-A) only boots the NVMe through a firmware boot
  entry. `nixos-install` writes it, but only from an installer booted in
  UEFI mode. CSM off, Secure Boot off.
- The new host and containers get fresh ssh keys, so the secrets have to be
  re-encrypted: set `startContainers = false` before installing, then on the
  host `systemctl start homelab-container-prepare; homelab-age-keys`, put the
  keys into `inventory/keys.nix` (`hosts.homelab`) and `inventory/nodes.nix`
  (`age`), `nix run .#sops-config`,
  `for f in $(git ls-files '*.enc.*'); do sops updatekeys -y "$f"; done`,
  set `startContainers = true` and deploy.
- Storage box: add `/etc/ssh/ssh_host_ed25519_key.pub` of the new host with
  `… | ssh -p23 u557074@u557074.your-storagebox.de install-ssh-key` from a
  machine that already has access.

### After every reboot

The HDD pool is encrypted and not unlocked automatically; containers with
data volumes wait for it:

```bash
zfs load-key threetbpool && zfs mount -a && systemctl start machines.target
```

## Housekeeping

```bash
nix flake update                    # all inputs
nix flake update tranquil           # one input (tranquil: bump the tag in flake.nix first)
nix fmt
```
