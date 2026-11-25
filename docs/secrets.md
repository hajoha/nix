# Secrets (sops-nix)

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

## Container keys

Each container decrypts its secrets with its own ssh host key, so a
compromised container can only read its own secrets. The keys come from
one of two places:

- **From the repo** (all new containers): `nix run .#new-node-key <node>`
  generates the key on the laptop. The private key is stored sops-encrypted
  in `hosts/homelab/container-keys.enc.json` (one JSON entry per node,
  readable by the homelab host and the admins), the matching `age` goes into
  `nodes.nix`. On the host, sops-nix decrypts it to
  `/run/secrets/container-key-<node>` and `homelab-container-prepare` copies
  it to `/var/lib/homelab/keys/<node>/` before the container starts.
- **Generated on the host** (containers that are not in that file):
  `homelab-container-prepare` creates the key on first start; read its age key
  on the host with `homelab-age-keys`, then add it to `nodes.nix` and deploy
  again.

```bash
nix run .#new-node-key nix-foo                       # new key for a node in nodes.nix

# move an existing host-generated key into the repo (age stays the same)
sops set hosts/homelab/container-keys.enc.json '["nix-foo"]' \
  "$(ssh root@10.60.0.4 cat /var/lib/homelab/keys/nix-foo/ssh_host_ed25519_key | jq -Rs .)"

# rotate a key: drop it, create a new one, re-encrypt the node's secrets
sops unset hosts/homelab/container-keys.enc.json '["nix-foo"]'
nix run .#new-node-key nix-foo
sops updatekeys -y services/foo/*.enc.yaml
deploy .#homelab && ssh root@10.60.0.4 systemctl restart container@nix-foo
```

Keys from the repo survive a reinstall of the host; only
`container-keys.enc.json` itself has to be re-encrypted for the new host key.

