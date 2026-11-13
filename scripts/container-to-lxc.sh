#!/usr/bin/env bash
# Undo homelab-import-lxc for one CT. Run ON PROXMOX (booted from its NVMe).
#
#   ./container-to-lxc.sh <vmid> <node-name>      e.g. 105 nix-postgres
#
# The LVM rootfs was only read by the migration, so only the mpN data
# subvolumes need to go back: rename <pool>/containers/<node>/<name> to
# <pool>/subvol-..., restore its mountpoint, re-apply the unprivileged id
# shift (+100000), set onboot: 1 and start the CT.
#
# Anything the NixOS container wrote meanwhile stays in those datasets; data
# that lived on the container root (<pool>/containers/<node>) is NOT copied
# back into the LVM rootfs, the CT continues from its pre-migration state.
set -euo pipefail

vmid=${1:?vmid}
name=${2:?node name}
pool=${POOL:-threetbpool}
conf=/etc/pve/lxc/$vmid.conf
ds=$pool/containers/$name
[ -f "$conf" ] || { echo "no $conf" >&2; exit 1; }

current_conf() { sed '/^\[/q' "$conf"; }

dirs=()
while read -r vol path; do
  [ -n "$vol" ] || continue
  sub=${vol#*:}
  child=$ds/$(basename "$path")
  if zfs list -H -o name "$child" >/dev/null 2>&1; then
    echo "== $child -> $pool/$sub"
    zfs rename "$child" "$pool/$sub"
    zfs set mountpoint="/$pool/$sub" "$pool/$sub"
    dirs+=("/$pool/$sub")
  else
    echo "-- $child not found, skipping $path"
  fi
done < <(current_conf | sed -n 's/^mp[0-9]*: *\([^,]*\),.*mp=\([^,]*\).*/\1 \2/p')

if [ ${#dirs[@]} -gt 0 ] && current_conf | grep -q '^unprivileged: *1'; then
  echo "== re-applying unprivileged id shift (+100000)"
  python3 - "${dirs[@]}" <<'PY'
import os, sys
def fix(i): return i + 100000 if i < 65536 else i
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
                    os.chmod(p, mode & 0o7777)
                n += 1
print(f"shifted {n} entries")
PY
fi

sed -i 's/^onboot: *0/onboot: 1/' "$conf"
pct start "$vmid"
echo "== $name ($vmid) is back on Proxmox"
