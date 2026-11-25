# Add a new service

1. Add an entry to `inventory/nodes.nix` (`ip`, `hostname`, `port`, `tcp`, …).
   Set `db = true;` if it needs a Postgres database.
2. Create `services/<name>/default.nix` (the directory defaults to the node
   name without `nix-`; override with `service = "…";`).
3. `nix run .#new-node-key <node>`: creates the container's ssh host key (its
   sops identity), writes `age = "…";` into the node, stores the private key
   encrypted in `hosts/homelab/container-keys.enc.json` (host + admins) and
   regenerates `.sops.yaml`.
4. Create the secrets (see below; with `db = true` also
   `services/<name>/postgres.enc.yaml` with a `password:` key).
5. `deploy .#homelab`. The host installs the key before the container starts,
   so the secrets decrypt on the first boot.
6. If it should be reachable from outside, add a vhost in
   `services/nginx/default.nix` (`vhost` / `proxy` helpers).

Containers created before this keep the key the host generated for them
(`homelab-age-keys` prints all of them).

Devices, extra capabilities or bind mounts for one container go into
`hosts/homelab/containers.nix` as plain `containers.<node>.*` options.


Monitoring needs nothing extra. The host's Alloy reads the new container's
journal, cAdvisor picks up its cgroup, it gets a tcp probe on `port`, and a
new vhost gets https probes ([monitoring.md](monitoring.md#a-new-container)).
