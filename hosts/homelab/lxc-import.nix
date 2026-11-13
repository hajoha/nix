# One-off import of the old Proxmox LXCs into the container datasets, run ON
# THE NIXOS HOST with the Proxmox NVMe (or its clone SSD, never both)
# attached (read-only use):
#
#   homelab-import-lxc                 all CTs below
#   homelab-import-lxc nix-paperless   just one
#
# Per CT:
#   - rootfs LV on the Proxmox disk (VG "pve", thin)  --rsync-->  <pool>/containers/<node>
#     (without /nix, /proc, ..., the mount points, and the old ssh host key:
#     every container gets a fresh key, secrets are re-encrypted)
#   - each data subvolume on the pool is renamed (no copy) to
#     <pool>/containers/<node>/<name>, mounted at the same path in the container
#   - the unprivileged uid/gid shift (100000) is undone
#
# The table is pve2's /etc/pve/lxc/*.conf as of 2026-11-13 (all unprivileged).
{
  config,
  lib,
  pkgs,
  params,
  ...
}:
let
  pool = params.pool;

  cts = {
    nix-unifi-controller.lv = "vm-100-disk-0";
    nix-opencloud = {
      lv = "vm-101-disk-0";
      mps."/var/lib/opencloud/data" = "subvol-101-disk-0";
    };
    nix-adguard.lv = "vm-103-disk-1";
    nix-postgres = {
      lv = "vm-105-disk-0";
      mps."/var/lib/postgresql" = "subvol-105-disk-0";
    };
    nix-arr = {
      lv = "vm-106-disk-0";
      mps."/data" = "subvol-106-disk-0";
    };
    nix-hedgedoc.lv = "vm-107-disk-0";
    nix-headscale.lv = "vm-108-disk-0";
    nix-sure.lv = "vm-109-disk-0";
    nix-grafana.lv = "vm-110-disk-0";
    nix-nginx.lv = "vm-111-disk-0";
    nix-keycloak.lv = "vm-112-disk-0";
    nix-immich = {
      lv = "vm-113-disk-0";
      mps."/var/lib/immich" = "subvol-113-disk-0";
    };
    nix-paperless.lv = "vm-114-disk-0";
    nix-homeassistant.lv = "vm-115-disk-1";
    nix-listmonk.lv = "vm-117-disk-0";
    nix-loki.lv = "vm-118-disk-0";
    nix-commafeed.lv = "vm-119-disk-0";
    nix-flathunter.lv = "vm-120-disk-0";
    nix-tranquil.lv = "vm-121-disk-0";
  };

  # "<node> <lv> <path>=<subvol> ..." per line
  table = pkgs.writeText "lxc-import-table" (
    lib.concatStrings (
      lib.mapAttrsToList (
        node: ct:
        "${node} ${ct.lv}"
        + lib.concatStrings (lib.mapAttrsToList (path: sub: " ${path}=${sub}") (ct.mps or { }))
        + "\n"
      ) cts
    )
  );

  shiftIds = pkgs.writeText "shift-ids.py" ''
    import os, sys
    def fix(i): return i - 100000 if 100000 <= i < 165536 else i
    n = 0
    for top in sys.argv[1:]:
        dev = os.lstat(top).st_dev
        for d, dirs, files in os.walk(top):
            dirs[:] = [x for x in dirs if os.lstat(os.path.join(d, x)).st_dev == dev]
            # dirs also holds symlinks to directories (not descended into)
            for p in ([d] if d == top else []) + [os.path.join(d, x) for x in dirs + files]:
                st = os.lstat(p)
                u, g = fix(st.st_uid), fix(st.st_gid)
                if (u, g) != (st.st_uid, st.st_gid):
                    mode = st.st_mode
                    os.lchown(p, u, g)
                    if not os.path.islink(p) and mode & 0o6000:
                        os.chmod(p, mode & 0o7777)  # chown clears setuid/setgid
                    n += 1
    print(f"  shifted {n} entries in {' '.join(sys.argv[1:])}")
  '';

  thinConf = "global { thin_check_executable = \"${pkgs.thin-provisioning-tools}/bin/thin_check\" }";

  importTool = pkgs.writeShellApplication {
    name = "homelab-import-lxc";
    runtimeInputs = [
      config.boot.zfs.package
      pkgs.lvm2
      pkgs.kmod
      pkgs.rsync
      pkgs.python3
      pkgs.util-linux
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
    ];
    text = ''
      pool=${pool}
      only=''${1:-}

      if systemctl list-units --state=running 'container@*' --no-legend | grep -q .; then
        echo "containers are running; stop them first (they must not see half-imported data)" >&2
        exit 1
      fi

      echo "== activating VG pve from the Proxmox disk"
      modprobe dm-thin-pool
      vgchange -ay pve --config '${thinConf}'
      src=/run/homelab-import/src
      mkdir -p "$src"
      # leftovers of an interrupted run
      while mountpoint -q "$src"; do umount "$src"; done
      trap 'while mountpoint -q "$src"; do umount "$src"; done' EXIT

      zfs list -H -o name "$pool/containers" >/dev/null 2>&1 ||
        zfs create -o mountpoint=none "$pool/containers"
      # journald & co. use POSIX ACLs; inherited by every container dataset
      zfs set acltype=posixacl xattr=sa "$pool/containers"

      while read -r node lv rest; do
        [ -n "$node" ] || continue
        read -ra mps <<<"$rest"
        [ -z "$only" ] || [ "$only" = "$node" ] || continue
        ds=$pool/containers/$node
        root=/var/lib/nixos-containers/$node
        echo "== $node ($lv)"

        # written after the id shift; a run that died halfway is simply redone
        # (rsync is incremental, the shift only touches ids >= 100000)
        if [ -e "$root/.homelab-imported" ]; then
          echo "  already imported, skipping"
          continue
        fi
        if ! zfs list -H -o name "$ds" >/dev/null 2>&1; then
          zfs create -o mountpoint="$root" "$ds"
        fi

        excludes=(--exclude=/nix --exclude=/proc --exclude=/sys --exclude=/dev
                  --exclude=/run --exclude=/tmp
                  --exclude=/etc/ssh/ssh_host_\*)
        for m in "''${mps[@]}"; do excludes+=("--exclude=''${m%%=*}"); done

        mount -o ro,noload "/dev/pve/$lv" "$src"
        rsync -aHAX --numeric-ids --info=progress2 "''${excludes[@]}" "$src/" "$root/"
        umount "$src"

        shiftdirs=("$root")
        for m in "''${mps[@]}"; do
          path=''${m%%=*}
          sub=$pool/''${m#*=}
          child=$ds/$(basename "$path")
          if zfs list -H -o name "$sub" >/dev/null 2>&1; then
            echo "  $sub -> $child ($path)"
            zfs snapshot "$sub@pre-migration"
            zfs rename "$sub" "$child"
            zfs set mountpoint="$root$path" "$child"
            shiftdirs+=("$root$path")
          elif zfs list -H -o name "$child" >/dev/null 2>&1; then
            echo "  $child already in place"
            shiftdirs+=("$root$path")
          else
            echo "  WARNING: neither $sub nor $child exists" >&2
          fi
        done

        python3 ${shiftIds} "''${shiftdirs[@]}"
        touch "$root/.homelab-imported"
      done < ${table}

      vgchange -an pve
      echo "== done. Next: systemctl start homelab-container-prepare; homelab-age-keys"
    '';
  };

  # Prints the age recipient of every container key (after
  # homelab-container-prepare generated them) and of the host.
  ageKeys = pkgs.writeShellApplication {
    name = "homelab-age-keys";
    runtimeInputs = [ pkgs.ssh-to-age ];
    text = ''
      printf '%-24s %s\n' "host (keys.hosts.pve2)" "$(ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub)"
      for d in /var/lib/homelab/keys/*/; do
        n=$(basename "$d")
        [ -f "$d/ssh_host_ed25519_key.pub" ] || continue
        printf '%-24s %s\n' "$n" "$(ssh-to-age < "$d/ssh_host_ed25519_key.pub")"
      done
    '';
  };
in
{
  environment.systemPackages = [
    importTool
    ageKeys
    pkgs.thin-provisioning-tools
  ];
}
