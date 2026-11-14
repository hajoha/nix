# homelab-deploy-rev <commit>: build that commit of main, switch to it,
# check that nothing broke, roll back otherwise. Runs as root (from
# homelab-deploy.service).
#
# exit 0: deployed (or already running), 1: rolled back, 3: build failed
# (nothing changed).
#
# "Broke" = compared with right before the switch: a container that ran is
# down, a unit (host or container) failed, or a container's inventory port
# stopped listening. Problems that already existed are ignored.
rev=${1:?commit}
[[ $rev =~ ^[0-9a-f]{40}$ ]] || { echo "not a commit hash: $rev" >&2; exit 2; }

exec 9>/run/homelab-deploy.lock
flock 9

profile=/nix/var/nix/profiles/system
state=/run/homelab-deploy
mkdir -p "$state"

echo "== building $rev"
new=$(nix build --no-link --print-out-paths --accept-flake-config \
  "$REPO_URL?ref=main&rev=$rev#nixosConfigurations.homelab.config.system.build.toplevel") \
  || { echo "== build failed, nothing changed"; exit 3; }
old=$(readlink -f "$profile")
if [ "$new" = "$(readlink -f /run/current-system)" ]; then
  echo "already running $new"
  exit 0
fi

running_containers() {
  { machinectl list --no-legend 2>/dev/null || true; } | awk '{print $1}'
}

# one line per problem
health() {
  { systemctl list-units --failed --plain --no-legend --type=service,mount,socket || true; } \
    | awk '{print "host: " $1 " failed"}'
  while read -r c port; do
    if ! systemctl is-active -q "container@$c"; then
      echo "$c: container not running"
      continue
    fi
    { systemctl -M "$c" list-units --failed --plain --no-legend 2>/dev/null || true; } \
      | awk -v c="$c" '{print c ": " $1 " failed"}'
    if [ "$port" != 0 ]; then
      leader=$(machinectl show "$c" -p Leader --value 2>/dev/null || true)
      if [ -n "$leader" ] && [ -z "$(nsenter -t "$leader" -n ss -Hltn "sport = :$port" 2>/dev/null)" ]; then
        echo "$c: port $port not listening"
      fi
    fi
  done < "$NODES"
}

# wait until host and containers have finished starting, then a bit longer
# for services that come up late or crash-loop
settle() {
  for _ in $(seq 60); do
    busy=0
    case $(systemctl is-system-running 2>/dev/null) in initializing | starting) busy=1 ;; esac
    for c in $(running_containers); do
      case $(systemctl -M "$c" is-system-running 2>/dev/null) in initializing | starting) busy=1 ;; esac
    done
    [ "$busy" = 0 ] && break
    sleep 10
  done
  sleep "$GRACE"
}

health | sort -u > "$state/before"
echo "== problems before the switch: $(grep -c . "$state/before")"
sed 's/^/   /' "$state/before"

snap=
if [ "$(zfs get -H -o value keystatus "$POOL" 2>/dev/null)" = available ]; then
  snap="deploy-$(date +%Y%m%d-%H%M)-${rev:0:8}"
  echo "== snapshot $POOL/containers@$snap"
  zfs snapshot -r "$POOL/containers@$snap" || snap=
fi

echo "== switching to $new"
nix-env -p "$profile" --set "$new"
switch_ok=1
"$new/bin/switch-to-configuration" switch || switch_ok=0

echo "== waiting for services to settle"
settle
health | sort -u > "$state/after"
comm -13 "$state/before" "$state/after" > "$state/new"

if [ "$switch_ok" = 1 ] && [ ! -s "$state/new" ]; then
  echo "== deployed $rev, no new problems"
  # keep the 10 newest deploy snapshots
  zfs list -H -t snapshot -o name -s creation "$POOL/containers" 2>/dev/null \
    | sed -n 's/.*@\(deploy-.*\)/\1/p' | head -n -10 \
    | while read -r s; do zfs destroy -r "$POOL/containers@$s" || true; done || true
  exit 0
fi

echo "== NEW PROBLEMS after the switch, rolling back to $old"
[ "$switch_ok" = 1 ] || echo "   switch-to-configuration failed"
sed 's/^/   /' "$state/new"
nix-env -p "$profile" --set "$old"
"$old/bin/switch-to-configuration" switch || true
settle
echo "== rolled back; problems compared with before the deploy:"
health | sort -u | comm -13 "$state/before" - | sed 's/^/   /' || true
echo "Data the new version wrote (e.g. database migrations) is not undone;"
echo "ZFS snapshot of the data datasets from right before the switch: ${snap:-none}"
exit 1
