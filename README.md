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
  lxc-import.nix        homelab-import-lxc / homelab-age-keys (one-off migration)
  disko.nix, image.nix  NVMe layout; raw image: nix build .#homelab-image
modules/
  nixos/homelab-host.nix   inventory -> containers.<name>, datasets, keys, VLANs
  nixos/container-base.nix base for every container
  nixos/homelab.nix        typed inventory (config.homelab), ssh-client, vm
  home/profiles/        base.nix (every machine), desktop.nix (niri/noctalia desktop)
  home/…                browser, mail, desktop, editor, programs
services/<name>/        one per container: default.nix + its *.enc.yaml secrets
hosts/<name>/           other machines (hardware, disko, home.nix)
scripts/                container-to-lxc.sh (undo the import on the Proxmox clone)
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
  inventory IP. The router sees each container as its own machine, exactly
  like the LXCs. (The host itself cannot talk to its containers over macvlan;
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
`nix-postgres`. Host secrets (`secrets/pve2.enc.yaml`, borg passphrase) use
the host key `pve2` in `inventory/keys.nix`.

```bash
nix run .#sops-config                         # after changing keys in inventory/
sops services/hedgedoc/secrets.enc.yaml       # create / edit
sops updatekeys services/hedgedoc/secrets.enc.yaml   # after recipients changed
nix flake check                               # also fails if .sops.yaml is stale
```

## Migrating from Proxmox

NixOS goes onto a separate 512G NVMe (Samsung PM9A1); the Proxmox NVMe
(WD SN770 1TB) is never written to. It is the import source for the LXC data
and the fallback; the dd clone on the SSD is an extra backup. Every machine
gets fresh ssh keys and the secrets are re-encrypted from the laptop (admin
keys can decrypt everything).

Disks: `PVE` = `/dev/disk/by-id/nvme-WD_BLACK_SN770_1TB_24453G405540`,
`NEW` = the Samsung, in the PC's adapter
`/dev/disk/by-id/ata-SAMSUNG_MZVL4512HBLU-00BL7_S67VNF1TB39494`.

### 1. Back up the Proxmox NVMe (PC, optional but done)

```bash
dd if=$PVE of=/dev/disk/by-id/<SSD> bs=64M iflag=fullblock conv=fsync status=progress
cmp -n $(blockdev --getsize64 $PVE) $PVE /dev/disk/by-id/<SSD> && echo CLONE OK
```

Afterwards never have the clone and `PVE` attached to the same machine at the
same time (identical LVM ids).

### 2. Install NixOS onto the 512G NVMe (PC)

`hosts/homelab/params.nix` has `startContainers = false`, so the first boot
brings up the host only. `disko-install` partitions the disk (layout from
`hosts/homelab/disko.nix`) and runs `nixos-install` onto it directly, with no
VM and no image. `--disk nvme` maps the config's disk to the name it has on
the PC.

```bash
D=$NEW
sudo wipefs -af $D-part* ; sudo wipefs -af $D ; sudo partprobe $D   # disko won't reformat existing filesystems
cd ~/git/home-nix
sudo env PATH="/nix/var/nix/profiles/system/sw/bin:/run/current-system/sw/bin:$PATH" \
  $(which nix) --extra-experimental-features 'nix-command flakes' \
  run 'github:nix-community/disko/latest#disko-install' -- \
  --flake "path:$PWD#homelab" --disk nvme $D
lsblk -o NAME,SIZE,PARTLABEL,FSTYPE,LABEL $D   # disk-nvme-ESP / -swap / -root
```

- The `PATH` is needed on non-NixOS (Ubuntu's sudo PATH has no `mount` for
  the chroot step).
- `setting up secrets… failed` is expected: no host key yet, secrets get
  re-encrypted in step 4.
- Evaluation needs ~7 GB RAM.
- If it fails, check `/mnt/disko-install-root`. When nothing is mounted there,
  remove it (`chattr -i …/var/empty` first, it is immutable).

Alternative without a disk attached: `nix build .#homelab-image` builds a raw
image in a VM (KVM, ~5 GB RAM) to `dd` onto the disk.

### 3. First boot (server: NEW + PVE + HDDs)

Put the Samsung into the server; `PVE` stays attached (second M.2 slot or a
USB adapter, or the clone SSD instead, never both). Select the Samsung in the
firmware boot menu (`efibootmgr -o` to make it permanent). The root partition
grows to the full disk, the pool is imported (same hostid), no container
starts. `ssh-keygen -R 10.60.0.4` on the laptop (new host key), then on the
host:

```bash
homelab-import-lxc                       # all CTs, or: homelab-import-lxc nix-paperless
zfs list -r threetbpool/containers       # every node + postgres/immich/arr/opencloud data
ls -ln /var/lib/nixos-containers/nix-postgres/var/lib/postgresql   # small uids, not 100xxx
systemctl start homelab-container-prepare   # generates the container ssh keys
homelab-age-keys                         # prints host + every container's age key
```

`homelab-import-lxc` copies each LXC rootfs from `PVE` (mounted read-only)
into `<pool>/containers/<node>` and renames the data subvolumes (postgres,
immich, arr, opencloud) into place (`@pre-migration` snapshot first),
undoing the unprivileged id shift. Afterwards `PVE` can be removed and kept
on the shelf.

Backup: add the host key `/etc/ssh/ssh_host_ed25519_key.pub` to the storage
box (Hetzner console → SSH keys), then `ssh backup-01 ls` and
`systemctl start borgmatic`.

### 4. Re-encrypt and start (laptop)

```bash
# paste the keys from homelab-age-keys:
#   inventory/nodes.nix  `age = "age1…";` per node
#   inventory/keys.nix   hosts.pve2
nix run .#sops-config
for f in $(git ls-files '*.enc.*'); do sops updatekeys -y "$f"; done
# hosts/homelab/params.nix: startContainers = true;
git commit -am "homelab: new keys, start containers"
deploy .#homelab
ssh root@10.60.0.4 systemctl start machines.target
```

Check: `machinectl`, `systemctl --failed`, `journalctl -M nix-postgres -u postgresql`,
`journalctl -M nix-paperless -b | grep -i sops`, the public vhosts.

### Going back to Proxmox

Boot from `PVE` again (put it back, pick it in the boot menu). Its LVM CTs
are as they were; only postgres, immich, arr and opencloud need their data
subvolume back: `scripts/container-to-lxc.sh <vmid> <node>` renames it back
and re-applies the +100000 id shift. Their Proxmox host key and CT keys are
unchanged, so the old secrets (git history before the re-encryption) still
work.

## Housekeeping

```bash
nix flake update                    # all inputs
nix flake update tranquil           # one input (tranquil: bump the tag in flake.nix first)
nix fmt
```
