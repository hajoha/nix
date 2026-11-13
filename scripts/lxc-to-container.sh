#!/usr/bin/env bash
# Run ON THE PROXMOX HOST, once per LXC, before NixOS replaces Proxmox.
#
#   ./lxc-to-container.sh <vmid> <node-name>      e.g. 114 nix-paperless
#
# Puts the LXC into the dataset layout the NixOS homelab host uses, on the
# ZFS pool, so it survives the reinstall:
#
#   <pool>/containers/<node>         -> /var/lib/nixos-containers/<node>
#       the rootfs (from local-lvm), copied without its private /nix store
#   <pool>/containers/<node>/<mp>    -> /var/lib/nixos-containers/<node><mp path>
#       every mpN that is a subvolume on <pool>: renamed (no copy), after a
#       @pre-migration snapshot
#   <pool>/homelab-keys              -> /var/lib/homelab/keys/<node>/
#       the ssh host key (= sops age identity, unchanged)
#
# Unprivileged CTs: the uid/gid shift (100000) is undone, NixOS containers
# run with the real ids. The CT is stopped and set to onboot: 0; its LVM
# rootfs is only read. Nothing is deleted.
set -euo pipefail

vmid=${1:?vmid}
name=${2:?node name, e.g. nix-paperless}
pool=${POOL:-threetbpool}
conf=/etc/pve/lxc/$vmid.conf
ds=$pool/containers/$name
keysds=$pool/homelab-keys
root=/var/lib/nixos-containers/$name
keys=/var/lib/homelab/keys/$name

[ -f "$conf" ] || { echo "no $conf" >&2; exit 1; }
if zfs list -H -o name "$ds" >/dev/null 2>&1; then
  echo "$ds already exists, refusing to overwrite" >&2
  exit 1
fi

# only the CT's current config, not [snapshot] sections
current_conf() { sed '/^\[/q' "$conf"; }

zfs list -H -o name "$keysds" >/dev/null 2>&1 ||
  zfs create -o mountpoint=/var/lib/homelab/keys "$keysds"
zfs list -H -o name "$pool/containers" >/dev/null 2>&1 ||
  zfs create -o mountpoint=none "$pool/containers"

echo "== stopping CT $vmid"
pct shutdown "$vmid" --timeout 120 2>/dev/null || pct stop "$vmid" 2>/dev/null || true
sed -i 's/^onboot: *1/onboot: 0/' "$conf"

# mount points that are subvolumes on $pool: "<dataset> <path in CT>"
mps=$(current_conf | sed -n 's/^mp[0-9]*: *\([^,]*\),.*mp=\([^,]*\).*/\1 \2/p' |
  while read -r vol path; do
    sub=$(zfs list -H -o name | grep -E "^${pool}/(.*/)?${vol#*:}\$" | head -1 || true)
    [ -n "$sub" ] && echo "$sub $path"
  done)

echo "== copying rootfs -> $ds"
zfs create -p -o mountpoint="$root" "$ds"
pct mount "$vmid" >/dev/null
excludes=(--exclude=/nix --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/run --exclude=/tmp)
while read -r _ path; do [ -n "$path" ] && excludes+=("--exclude=$path"); done <<<"$mps"
rsync -aHAX --numeric-ids --info=progress2 "${excludes[@]}" \
  "/var/lib/lxc/$vmid/rootfs/" "$root/"
pct unmount "$vmid"

shiftdirs=("$root")
while read -r sub path; do
  [ -n "$sub" ] || continue
  child=$ds/$(basename "$path")
  echo "== $sub ($path) -> $child"
  zfs snapshot "$sub@pre-migration"
  zfs rename "$sub" "$child"
  zfs set mountpoint="$root$path" "$child"
  shiftdirs+=("$root$path")
done <<<"$mps"

install -d -m 700 "$keys"
cp -a "$root/etc/ssh/ssh_host_ed25519_key" "$root/etc/ssh/ssh_host_ed25519_key.pub" "$keys/"
chown root:root "$keys"/*
chmod 600 "$keys/ssh_host_ed25519_key"

if current_conf | grep -q '^unprivileged: *1'; then
  echo "== unprivileged CT: shifting uids/gids back by 100000"
  python3 - "${shiftdirs[@]}" <<'PY'
import os, sys
def fix(i): return i - 100000 if 100000 <= i < 165536 else i
n = 0
for top in sys.argv[1:]:
    dev = os.lstat(top).st_dev
    for d, dirs, files in os.walk(top):
        dirs[:] = [x for x in dirs if os.lstat(os.path.join(d, x)).st_dev == dev]
        for p in [d] + [os.path.join(d, f) for f in files]:
            st = os.lstat(p)
            u, g = fix(st.st_uid), fix(st.st_gid)
            if (u, g) != (st.st_uid, st.st_gid):
                mode = st.st_mode
                os.lchown(p, u, g)
                if not os.path.islink(p) and mode & 0o6000:
                    os.chmod(p, mode & 0o7777)  # chown clears setuid/setgid
                n += 1
print(f"shifted {n} entries")
PY
fi

echo "== done: $name"
zfs list -r -o name,used,mountpoint "$ds"
