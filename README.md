# home-nix

NixOS + home-manager config for the homelab (Proxmox LXCs), the desktop
(`nixmaschine`), the work laptop (`haa`, standalone home-manager), a Hetzner
VPS and a Raspberry Pi.

## Layout

```
flake.nix               inputs + wiring only
flake/
  lxc.nix               builds every LXC + its deploy-rs node from the inventory
  hosts.nix             nixmaschine, hetzner-vps-01, pi3-sendspin, homeConfigurations.haa
inventory/
  nodes.nix             ONE entry per LXC: ip, port, names, firewall, db, age key
  keys.nix              admin + non-LXC age keys
  default.nix           derives networking etc. from nodes.nix
  sops.nix              generates .sops.yaml
modules/
  nixos/                homelab (typed inventory), lxc-base, ssh-client, vm
  home/profiles/        base.nix (every machine), desktop.nix (niri/noctalia desktop)
  home/…                browser, mail, desktop, editor, programs
services/<name>/        one per LXC: default.nix + its *.enc.yaml secrets
hosts/<name>/           real machines (hardware, disko, home.nix)
pkgs/                   local packages
secrets/                secrets not tied to a service
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

## Add a new LXC service

1. Add an entry to `inventory/nodes.nix` (`ip`, `hostname`, `port`, `tcp`, …).
   Set `db = true;` if it needs a Postgres database.
2. Create `services/<name>/default.nix` (the directory defaults to the node
   name without `nix-`; override with `service = "…";`).
3. Create the container in Proxmox, then add its age key:
   `ssh-keyscan <ip> | ssh-to-age` → `age = "age1…";` on the node.
4. `nix run .#sops-config` to regenerate `.sops.yaml`, then create secrets
   (see below). With `db = true`, also create `services/<name>/postgres.enc.yaml`
   with a `password:` key and deploy `nix-postgres`.
5. If it should be reachable from outside, add a vhost in
   `services/nginx/default.nix` (`vhost` / `proxy` helpers).
6. `deploy .#nix-<name>`

## Deploy

```bash
nix develop                         # sops, age, ssh-to-age, deploy-rs
deploy .#nix-nginx                  # one LXC (ssh alias home-nix-nginx)
deploy .                            # every node without `deploy = false`
deploy .#nix-nginx --dry-activate   # dry run
deploy .#nix-nginx -- --builders 'ssh://home-nix-build x86_64-linux'

sudo nixos-rebuild switch --flake .#nixmaschine
home-manager switch --flake .#haa
```

## Secrets (sops-nix)

`.sops.yaml` is generated, so don't edit it by hand. A service's
`services/<svc>/*.enc.yaml` can be decrypted by that node's `age` key, by its
`sopsReaders`, and by the admin keys; `postgres.enc.yaml` also by
`nix-postgres`.

```bash
nix run .#sops-config                         # after changing keys in inventory/
sops services/hedgedoc/secrets.enc.yaml       # create / edit
sops updatekeys services/hedgedoc/secrets.enc.yaml   # after recipients changed
nix flake check                               # also fails if .sops.yaml is stale
```

## Housekeeping

```bash
nix flake update                    # all inputs
nix flake update tranquil           # one input (tranquil: bump the tag in flake.nix first)
nix fmt
sudo nix-collect-garbage --delete-older-than 2d
```
