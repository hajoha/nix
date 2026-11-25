# Deploy

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

## Updates and deploys (GitHub)

`main` is what runs on the homelab host. GitHub tells it about new PRs and
pushes through two webhooks; no timer, no GitHub runner on the host.
nix-nginx forwards `https://hooks.hackler.io/hooks/{preview,deploy}` to the
`nix-hooks` container (service VLAN, reachable only from nix-nginx). It
accepts only requests signed with the shared secret and then just drops an
empty file (`deploy`, `preview-<pr>`) into a directory shared with the host;
`homelab-hooks.path` on the host notices it and starts the unit. There is no
network path from the service VLAN to the host. The host fetches the repo
and asks the GitHub API itself, and never builds PRs from forks.

- **Every Monday** `update-flake-lock.yaml` (on GitHub's machines) runs
  `nix flake update` and opens or refreshes the PR "flake.lock: update".
- **Every PR** from a branch of this repo into `main` (opened / pushed to):
  `homelab-preview@<pr>` builds the PR's system and comments (one comment,
  updated on every push)
  - the package version changes per container (`nvd diff` of each
    container's system),
  - the version changes of the whole system,
  - CVEs fixed / new / still open (`vulnix`; matched by package name and
    version, so a hint: false positives and backported patches happen).
    Still open ones are grouped by package with their severity, critical
    and high (CVSS ≥ 7) listed. CVEs checked by hand and found irrelevant
    go into `hosts/homelab/ci/vulnix-whitelist.toml` (format in the file);
    they stop counting once that is deployed.

  The commit gets the status `homelab/preview` (red if it does not build).
- **Every push to `main`** (e.g. merging a PR): `homelab-deploy` builds
  `main`, takes a ZFS snapshot of the data datasets, switches, waits until
  the host and all containers have settled (+90 s), and compares with right
  before the switch:
  - a container that ran is down,
  - a unit failed (host or inside a container),
  - a container's inventory `port` is no longer listening.

  Anything new → it switches back to the previous system. The result goes
  to the commit status `homelab/deploy` and as a comment on the merged PR.
  Problems that existed before are ignored. Data a new version wrote
  (database migrations) is not rolled back; the `@deploy-…` snapshot (last
  10 kept) has the state from right before.

```bash
journalctl -u homelab-deploy -n 100           # last deploys
journalctl -u 'homelab-preview@*' -n 100      # last previews
journalctl -M nix-hooks -u webhook -n 50      # incoming hooks
journalctl -u homelab-hooks -n 50             # what the host started
systemctl start homelab-deploy                # deploy main now, by hand
homelab-preview /nix/var/nix/profiles/system-123-link   # preview against any system
```

Manual deploys (`deploy .#homelab`, `nixos-rebuild`) still work and stay
until the next push to `main`.

One-time setup:

1. Key for the new container: `nix run .#new-node-key nix-hooks`.
2. A webhook secret (`openssl rand -hex 32`) for nix-hooks:
   `sops services/hooks/secrets.enc.yaml` → `webhook-secret: <hex>`.
   The webhook server runs as soon as this file exists.
3. A fine-grained PAT (GitHub → Settings → Developer settings), only for
   this repo, with **Pull requests: Read and write** and **Commit
   statuses: Read and write**, for the host:
   `sops hosts/homelab/github.enc.yaml` → `token: github_pat_…`.
   Comments appear under your account.
4. Repo → Settings → Webhooks, two of them, both with content type
   `application/json` and the secret from 2.:
   - `https://hooks.hackler.io/hooks/preview`, event **Pull requests**
   - `https://hooks.hackler.io/hooks/deploy`, event **Pushes**

   `hooks.hackler.io` must resolve publicly to the edge, like the other
   public vhosts.
5. Repo → Settings → Actions → General → Workflow permissions: allow GitHub
   Actions to create and approve pull requests (for the flake.lock PR).
6. Deploy once by hand. GitHub's webhook page shows each delivery and its
   response ("Redeliver" to retry one).


## Housekeeping

```bash
nix flake update                    # all inputs
nix flake update tranquil           # one input (tranquil: bump the tag in flake.nix first)
nix fmt
```
