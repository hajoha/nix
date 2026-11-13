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
  backup.nix            borgmatic to backup-01 (ZFS snapshots)
modules/
  nixos/homelab-host.nix   inventory -> containers.<name>, datasets, keys, VLANs
  nixos/container-base.nix base for every container
  nixos/homelab.nix        typed inventory (config.homelab), ssh-client, vm
  home/profiles/        base.nix (every machine), desktop.nix (niri/noctalia desktop)
  home/…                browser, mail, desktop, editor, programs
services/<name>/        one per container: default.nix + its *.enc.yaml secrets
hosts/<name>/           other machines (hardware, disko, home.nix)
scripts/                lxc-to-container.sh (one-off Proxmox migration)
pkgs/                   local packages
secrets/                secrets not tied to a service
```

## How the homelab host works

- Each inventory node with a `service` becomes `containers.<node>` (systemd-nspawn).
  Containers share the host's `/nix/store` (read-only): one store, one GC,
  one deploy for everything.
- Container root = ZFS dataset `<pool>/containers/<node>` mounted at
  `/var/lib/nixos-containers/<node>`; sanoid snapshots them
  (hourly 24, daily 14, monthly 3).
- Networking: the host has one VLAN interface per network (`service`, `iot`,
  `dmz`, `wireguard`, ids in `params.nix`) without an address. Every container
  gets a macvlan on each VLAN it uses, renamed inside to the VLAN name, and its
  inventory IP. The router sees each container as its own machine, exactly
  like the LXCs. (The host itself cannot talk to its containers over macvlan;
  use `nixos-container root-login <node>` or go via the router.)
- Secrets: every container keeps its old ssh host key
  (`/var/lib/homelab/keys/<node>`, bind-mounted read-only), so its age key in
  `nodes.nix` and `.sops.yaml` are unchanged. A new node gets a key generated
  on first start.

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

# or on the box itself
nixos-rebuild switch --flake .#homelab

sudo nixos-rebuild switch --flake .#nixmaschine
home-manager switch --flake .#haa
```

## Secrets (sops-nix)

`.sops.yaml` is generated, so don't edit it by hand. A service's
`services/<svc>/*.enc.yaml` can be decrypted by that node's `age` key, by its
`sopsReaders`, and by the admin keys; `postgres.enc.yaml` also by
`nix-postgres`. Host secrets (`secrets/pve2.enc.yaml`, borg passphrase) use
the host key `pve2` in `inventory/keys.nix`.

```bash
nix run .#sops-config                         # after changing keys in inventory/
sops services/hedgedoc/secrets.enc.yaml       # create / edit
sops updatekeys services/hedgedoc/secrets.enc.yaml   # after recipients changed
nix flake check                               # also fails if .sops.yaml is stale
```

## Migrating from Proxmox

### 1. Parameters

Already read off pve2 and filled into `hosts/homelab/params.nix` and
`hardware.nix` (hostid, NIC + MAC, VLANs 3001/3050/3060, mgmt 10.60.0.4,
Intel P530, radio, storage box). To re-check:

```bash
hostid; zpool status; zfs list; lvs; lsblk; ip -br addr; cat /etc/network/interfaces
for f in /etc/pve/lxc/*.conf; do echo "--- $f"; sed '/^\[/q' $f; done
```

### 2. Move every LXC onto the pool (on pve2, right before the install)

Make sure the LVM thin pool is not full (`lvs`: `data` Data%), then:

```bash
for m in 100:nix-unifi-controller 101:nix-opencloud 103:nix-adguard \
         105:nix-postgres 106:nix-arr 107:nix-hedgedoc 108:nix-headscale \
         109:nix-sure 110:nix-grafana 111:nix-nginx 112:nix-keycloak \
         113:nix-immich 114:nix-paperless 115:nix-homeassistant \
         117:nix-listmonk 118:nix-loki 119:nix-commafeed \
         120:nix-flathunter 121:nix-tranquil; do
  ./scripts/lxc-to-container.sh ${m%%:*} ${m#*:} || break
done
```

(102 nix-build is retired, 104 claude-code and 116 sparkyfitness are not in
the repo.) Per CT, the LVM rootfs is copied into `<pool>/containers/<node>`;
every `mpN` that is a subvolume on the pool (postgres, immich, arr,
opencloud) is renamed to a child dataset mounted at the same path inside the
container root (no copy); unprivileged id shifts are undone; the ssh host key
goes to `<pool>/homelab-keys` (mounted at `/var/lib/homelab/keys`). Then save
the host's own keys there too:

```bash
K=/var/lib/homelab/keys        # mountpoint of <pool>/homelab-keys
install -d -m 700 $K/_host
cp /etc/ssh/ssh_host_ed25519_key* $K/_host/     # host key (sops recipient pve2)
cp -r /root/.ssh $K/_host/root-ssh              # storage box key for borgmatic
pct pull 102 /etc/nix/signing-key.sec $K/_host/signing-key.sec   # if nix-build signed
```

### 3. Install NixOS next to Proxmox

pve2's NVMe has ~455 G unpartitioned after Proxmox' LVM (p1-p3). NixOS gets
its own ESP and root there, Proxmox stays bootable from the firmware boot
menu (F11) as a fallback. Both use the same hostid (`c78d3ae7`), so the pool
imports on either without `-f`, but never `zpool upgrade` while Proxmox is
still the fallback.

Boot the NixOS installer (USB), then:

```bash
# new partitions in the free space at the end of the NVMe
sgdisk -n 4:0:+1G -t 4:ef00 -c 4:NIXBOOT -n 5:0:0 -t 5:8300 -c 5:nixos /dev/nvme0n1
mkfs.vfat -F32 -n NIXBOOT /dev/nvme0n1p4
mkfs.ext4 -L nixos /dev/nvme0n1p5
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot && mount /dev/disk/by-label/NIXBOOT /mnt/boot

zpool import -f -R /mnt threetbpool
K=/mnt/var/lib/homelab/keys/_host
install -d -m 700 /mnt/etc/ssh /mnt/root/.ssh /mnt/etc/nix
cp $K/ssh_host_ed25519_key* /mnt/etc/ssh/
cp $K/root-ssh/id_ed25519_hetzner* $K/root-ssh/known_hosts /mnt/root/.ssh/
cp $K/signing-key.sec /mnt/etc/nix/ 2>/dev/null || true

git clone https://github.com/hajoha/nix /tmp/home-nix && cd /tmp/home-nix
git switch nixos-host
nixos-generate-config --show-hardware-config   # compare with hosts/homelab/hardware.nix
nixos-install --flake .#homelab --no-root-passwd
zpool export threetbpool
reboot
```

systemd-boot becomes the default boot entry; pick "Proxmox"/"debian" in the
firmware boot menu to go back. Note that after step 2 the Proxmox CTs are
stopped and their data datasets renamed, so Proxmox is a fallback for the
host, not for the services (`zfs rename` back + `onboot: 1` to undo a CT).

## Housekeeping

```bash
nix flake update                    # all inputs
nix flake update tranquil           # one input (tranquil: bump the tag in flake.nix first)
nix fmt
```
